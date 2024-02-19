// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract FlashLiquidityPairMock {

    address public token0;
    address public token1;
    address public manager;

    constructor(address _token0, address _token1, address _manager) {
        token0 = _token0;
        token1 = _token1;
        manager = _manager; 
    }

    function setManager(address _manager) external {
        manager = _manager;
    }

    // skip coverage
    function test() external {}
}

