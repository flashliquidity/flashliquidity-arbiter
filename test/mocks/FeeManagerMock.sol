// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract FeeManagerMock {

    address public immutable i_linkAddress;

    constructor(address linkAddress) {
        i_linkAddress = linkAddress;
    }

    // skip coverage
    function test() external {}
}

