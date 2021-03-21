// SPDX-License-Identifier: MIT
// Adapted from https://github.com/studydefi/money-legos/blob/master/src/dydx/contracts/ISoloMargin.sol
pragma solidity ^0.8.0;

library Account {
    struct Info {
        address owner; // The address that owns the account
        uint256 number; // A nonce that allows a single address to control many accounts
    }
}


library Actions {
    enum ActionType {
        Deposit, // supply tokens
        Withdraw, // borrow tokens
        Transfer, // transfer balance between accounts
        Buy, // buy an amount of some token (publicly)
        Sell, // sell an amount of some token (publicly)
        Trade, // trade tokens against another account
        Liquidate, // liquidate an undercollateralized or expiring account
        Vaporize, // use excess tokens to zero-out a completely negative account
        Call // send arbitrary data to an address
    }

    struct ActionArgs {
        ActionType actionType;
        uint256 accountId;
        Types.AssetAmount amount;
        uint256 primaryMarketId;
        uint256 secondaryMarketId;
        address otherAddress;
        uint256 otherAccountId;
        bytes data;
    }
}


library Types {
    enum AssetDenomination {
        Wei, // the amount is denominated in wei
        Par // the amount is denominated in par
    }

    enum AssetReference {
        Delta, // the amount is given as a delta from the current value
        Target // the amount is given as an exact number to end up at
    }

    struct AssetAmount {
        bool sign; // true if positive
        AssetDenomination denomination;
        AssetReference ref;
        uint256 value;
    }
}


interface ISoloMargin {

    function getMarketTokenAddress(uint256 marketId) external view returns (address);

    function getNumMarkets() external view returns (uint256);

    function operate(Account.Info[] memory accounts, Actions.ActionArgs[] memory actions) external;
}
