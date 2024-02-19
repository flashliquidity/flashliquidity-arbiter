// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

library ChainlinkCommon {
    // @notice The asset struct to hold the address of an asset and amount
    struct Asset {
        address assetAddress;
        uint256 amount;
    }

    // @notice Struct to hold the address and its associated weight
    struct AddressAndWeight {
        address addr;
        uint64 weight;
    }
}
