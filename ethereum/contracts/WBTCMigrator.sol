// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";

// Import Compound components
import "./external/compound/CERC20.sol";
import "./external/compound/CEther.sol";
import "./external/compound/Comptroller.sol";
import "./external/compound/UniswapAnchoredView.sol";

// Import AAVE components
import "./external/aave/FlashLoanReceiverBase.sol";
import "./external/aave/ILendingPoolAddressesProvider.sol";

// Import KeeperDAO components
import "./external/keeperdao/ILiquidityPool.sol";

import "./external/IWETH.sol";


contract WBTCMigrator is FlashLoanReceiverBase {
    using SafeERC20 for IERC20;

    event Migrated(address indexed account, uint256 underlyingV1, uint256 underlyingV2);

    address payable private constant KEEPER_LIQUIDITY_POOL = payable(0x35fFd6E268610E764fF6944d07760D0EFe5E40E5);
    address private constant KEEPER_BORROW_PROXY = 0xde92742213FEa5f78c6840B6EcBf214115ea8002;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private constant CWBTC1 = 0xC11b1268C1A384e55C48c2391d8d480264A3A7F4;
    address private constant CWBTC2 = 0xccF4429DB6322D5C611ee964527D42E5d685DD6a;
    address private constant CETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    Comptroller public immutable comptroller;

    UniswapAnchoredView public immutable priceOracle;

    receive() external payable {}

    constructor(ILendingPoolAddressesProvider _provider, address _comptroller) FlashLoanReceiverBase(_provider) {
        comptroller = Comptroller(_comptroller);
        priceOracle = UniswapAnchoredView(Comptroller(_comptroller).oracle());

        // Enter the cETH market now so that we don't have to do it ad-hoc during KeeperDAO loans
        address[] memory markets = new address[](1);
        markets[0] = CETH;
        Comptroller(_comptroller).enterMarkets(markets);
    }

    /**
     * @notice Like `migrate()`, allows msg.sender to migrate collateral from
     *      cWBTCv1 to cWBTCv2, so long as msg.sender has already approve this contract
     *      to transfer their cWBTCv1.
     *
     *      This version of the function returns early if it detects that msg.sender can't
     *      be migrated. It also looks for WBTC dust after the transaction, and if any
     *      exists it will be sent back to msg.sender
     *
     * @param gasOptimized When true, borrow WBTC directly (from AAVE, 0.09% fee).
     *      When false, get WBTC indirectly (from KeeperDAO, higher gas usage).
     */
    function migrateWithExtraChecks(bool gasOptimized) external {
        if (CERC20(CWBTC1).balanceOf(msg.sender) == 0) return;

        ( , , uint256 shortfall) = comptroller.getAccountLiquidity(msg.sender);
        if (shortfall != 0) return;

        address[] memory enteredMarkets = comptroller.getAssetsIn(msg.sender);
        for (uint256 i = 0; i < enteredMarkets.length; i++) {
            if (enteredMarkets[i] != CWBTC2) continue;

            migrate(gasOptimized);

            uint256 dust = IERC20(WBTC).balanceOf(address(this));
            if (dust != 0) IERC20(WBTC).transfer(msg.sender, dust);
        }
    }

    /**
     * @notice Allows msg.sender to migrate collateral from cWBTCv1 to cWBTCv2, so long
     *      as msg.sender has already approve this contract to transfer their cWBTCv1.
     *
     *      WARNING: This is made possible by AAVE flash loans, which means migration will incur
     *      a 0.09% loss in underlying WBTC
     *
     * @param gasOptimized When true, borrow WBTC directly (from AAVE, 0.09% fee).
     *      When false, get WBTC indirectly (from KeeperDAO, higher gas usage).
     */
    function migrate(bool gasOptimized) public {
        uint256 supplyV1 = CERC20(CWBTC1).balanceOf(msg.sender);
        require(supplyV1 > 0, "0 balance no migration needed");
        require(IERC20(CWBTC1).allowance(msg.sender, address(this)) >= supplyV1, "Please approve for cWBTCv1 transfers");

        // fetch the flash loan premium from AAVE. (ex. 0.09% fee would show up as `9` here)
        uint256 premium = LENDING_POOL.FLASHLOAN_PREMIUM_TOTAL();
        uint256 exchangeRateV1 = CERC20(CWBTC1).exchangeRateCurrent();

        uint supplyV2Underlying;

        if (gasOptimized) {
            supplyV2Underlying = supplyV1 * exchangeRateV1 * (10_000 - premium) / 1e22;
            bytes memory params = abi.encode(msg.sender, supplyV1);

            initiateAAVEFlashLoan(WBTC, supplyV2Underlying, params);

        } else {
            supplyV2Underlying = supplyV1 * exchangeRateV1 / 1e18;
            ( , uint256 collatFact, ) = comptroller.markets(CETH);
            uint256 dollarsPerETH = priceOracle.getUnderlyingPrice(CETH);
            uint256 dollarsPerBTC = priceOracle.getUnderlyingPrice(CWBTC1);
            uint256 requiredETH = supplyV2Underlying * 1e18 * dollarsPerBTC / dollarsPerETH / collatFact;

            initiateKeeperFlashloan(msg.sender, requiredETH, supplyV1, supplyV2Underlying - 1);
        }
        
        emit Migrated(msg.sender, supplyV1 * exchangeRateV1 / 1e18, supplyV2Underlying);
    }

    /// @dev When this is called, contract's WBTC balance should be _supplyV2Underlying. After this has run,
    ///      the contract's WBTC balance will be _supplyV1 * exchangeRateV1.
    function flashloanInner(
        address _account,
        uint256 _supplyV1,
        uint256 _supplyV2Underlying
    ) internal {
        // Mint v2 tokens and send them to _account
        IERC20(WBTC).approve(CWBTC2, _supplyV2Underlying);
        require(CERC20(CWBTC2).mint(_supplyV2Underlying) == 0, "Failed to mint cWBTCv2");
        require(IERC20(CWBTC2).transfer(_account, IERC20(CWBTC2).balanceOf(address(this))), "Failed to send cWBTCv2");

        // Pull and redeem v1 tokens from _account
        require(IERC20(CWBTC1).transferFrom(_account, address(this), _supplyV1), "Failed to receive cWBTCv1");
        require(CERC20(CWBTC1).redeem(_supplyV1) == 0, "Failed to redeem cWBTCv1");
    }

    /// @dev Meant to be called by AAVE Lending Pool, but be careful since anyone might call it
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(msg.sender == address(LENDING_POOL), "Flash loan initiated by outsider");
        require(initiator == address(this), "Flash loan initiated by outsider");
        (address account, uint256 supplyV1) = abi.decode(params, (address, uint256));

        // Execute main migration logic
        flashloanInner(account, supplyV1, amounts[0]);
        
        // Get ready to repay flashloan
        IERC20(WBTC).approve(address(LENDING_POOL), amounts[0] + premiums[0]);
        // Finish up
        return true;
    }

    function initiateAAVEFlashLoan(address _token, uint256 _amount, bytes memory params) internal {
        address[] memory assets = new address[](1);
        assets[0] = _token;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _amount;

        uint256[] memory modes = new uint256[](1);
        modes[0] = 0; // 0 = no debt, 1 = stable, 2 = variable

        LENDING_POOL.flashLoan(
            address(this),
            assets,
            amounts,
            modes,
            address(this),
            params,
            0
        );
    }

    /// @dev Meant to be called by KeeperDAO Borrow Proxy, but be careful since anyone might call it
    function keeperFlashloanCallback(address _account, uint256 _amountETH, uint256 _supplyV1, uint256 _supplyV2Underlying) external {
        require(msg.sender == KEEPER_BORROW_PROXY, "Flashloan initiated by outsider");

        // Use the borrowed ETH to get WBTC
        CEther(CETH).mint{value: _amountETH}();
        require(CERC20(CWBTC2).borrow(_supplyV2Underlying) == 0, "Failed to borrow WBTC");

        // Execute main migration logic
        flashloanInner(_account, _supplyV1, _supplyV2Underlying);

        // Get ready to repay flashloan (get original ETH back)
        IERC20(WBTC).approve(CWBTC2, _supplyV2Underlying);
        require(CERC20(CWBTC2).repayBorrow(_supplyV2Underlying) == 0, "Failed to repay WBTC borrow");
        require(CEther(CETH).redeemUnderlying(_amountETH) == 0, "Failed to retrieve original ETH");
        // Finish up
        KEEPER_LIQUIDITY_POOL.send(_amountETH + 1);
    }

    function initiateKeeperFlashloan(address _account, uint256 _amountETH, uint256 _supplyV1, uint256 _supplyV2Underlying) internal {
        ILiquidityPool(KEEPER_LIQUIDITY_POOL).borrow(
            // Address of the token we want to borrow. Using this address
            // means that we want to borrow ETH.
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            // The amount of WEI that we will borrow. We have to return at least
            // more than this amount.
            _amountETH,
            // Encode the callback into calldata. This will be used to call a
            // function on this contract.
            abi.encodeWithSelector(
                // Function selector of the callback function.
                this.keeperFlashloanCallback.selector,
                // Function arguments
                _account,
                _amountETH,
                _supplyV1,
                _supplyV2Underlying
            )
        );
    }
}
