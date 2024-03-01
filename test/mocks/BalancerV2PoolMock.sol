// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract BalancerV2PoolMock {

    bytes32 public s_poolId;

    constructor(bytes32 poolId) {
        s_poolId = poolId; 
    }

    function getPoolId() external view returns (bytes32) {
        return s_poolId;
    }

    // skip coverage
    function test() external {}
}

