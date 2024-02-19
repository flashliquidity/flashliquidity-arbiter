// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract VerifierProxyMock {

    address public s_feeManager;

    struct BasicReport {
        bytes32 feedId; // The feed ID the report has data for
        uint32 validFromTimestamp; // Earliest timestamp for which price is applicable
        uint32 observationsTimestamp; // Latest timestamp for which price is applicable
        uint192 nativeFee; // Base cost to validate a transaction using the report, denominated in the chain’s native token (WETH/ETH)
        uint192 linkFee; // Base cost to validate a transaction using the report, denominated in LINK
        uint64 expiresAt; // Latest timestamp where the report can be verified on-chain
        int192 price; // DON consensus median price, carried to 8 decimal places
    }
    
    constructor(address feeManager) {
        s_feeManager = feeManager; 
    }

    // skip coverage
    function test() external {}
}

