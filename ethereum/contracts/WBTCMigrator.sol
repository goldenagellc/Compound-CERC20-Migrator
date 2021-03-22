// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";

// Import Compound components
import "./external/compound/CERC20.sol";
import "./external/compound/CEther.sol";
import "./external/compound/Comptroller.sol";
import "./external/compound/UniswapAnchoredView.sol";

// Import AAVE components
import "./external/aave/FlashLoanReceiverBase.sol";
import "./external/aave/ILendingPoolAddressesProvider.sol";

import "./external/IWETH.sol";


contract WBTCMigrator is FlashLoanReceiverBase {
    using SafeERC20 for IERC20;

    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private constant CWBTC1 = 0xC11b1268C1A384e55C48c2391d8d480264A3A7F4;
    address private constant CWBTC2 = 0xccF4429DB6322D5C611ee964527D42E5d685DD6a;

    constructor(ILendingPoolAddressesProvider provider) FlashLoanReceiverBase(provider) {

    }

    function migrateWithExtraChecks(address account) external {
        if (CERC20(CWBTC1).balanceOf(account) == 0) return;

        ( , uint liquidity1, uint shortfall1) = Comptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B).getAccountLiquidity(account);
        if (shortfall1 != 0) return;

        migrate(account);
        ( , uint liquidity2, uint shortfall2) = Comptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B).getAccountLiquidity(account);

        require(liquidity1 == liquidity2 && shortfall1 == shortfall2, "Oops. Account health mismatch");
        require(IERC20(WBTC).balanceOf(address(this)) == 0, "Oops. Migration contract profited");
    }

    function migrate(address account) public {
        uint256 supplyV1 = CERC20(CWBTC1).balanceOf(account);
        require(supplyV1 > 0, "0 balance no migration needed");
        require(IERC20(CWBTC1).allowance(account, address(this)) >= supplyV1, "Please approve for cWBTCv1 transfers");

        // fetch the flash loan premium from AAVE. (ex. 0.09% fee would show up as `9` here)
        uint256 premium = LENDING_POOL.FLASHLOAN_PREMIUM_TOTAL();
        uint256 exchangeRateV1 = CERC20(CWBTC1).exchangeRateCurrent();
        uint256 supplyV2Underlying = supplyV1 * exchangeRateV1 * (10_000 - premium) / 10_000; // 18 extra decimals

        bytes memory params = abi.encode(account, supplyV1);
        initiateFlashLoan(WBTC, supplyV2Underlying / 1e18, params);
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(msg.sender == address(LENDING_POOL), "Flash loan initiated by outsider");
        require(initiator == address(this), "Flash loan initiated by outsider");

        // retrieve params. also note that amounts[0] is supplyV2Underlying
        (address account, uint256 supplyV1) = abi.decode(params, (address, uint256));

        // Mint v2 tokens and send them to account
        IERC20(WBTC).approve(CWBTC2, amounts[0]);
        require(CERC20(CWBTC2).mint(amounts[0]) == 0, "Failed to mint cWBTCv2");
        require(IERC20(CWBTC2).transfer(account, IERC20(CWBTC2).balanceOf(address(this))), "Failed to send cWBTCv2");

        // Pull and redeem v1 tokens from account
        require(IERC20(CWBTC1).transferFrom(account, address(this), supplyV1), "Failed to receive cWBTCv1");
        require(CERC20(CWBTC1).redeem(supplyV1) == 0, "Failed to redeem cWBTCv1");
        IERC20(WBTC).approve(address(LENDING_POOL), amounts[0] + premiums[0]);

        return true;
    }

    function initiateFlashLoan(address _token, uint256 _amount, bytes memory params) internal {
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
}
