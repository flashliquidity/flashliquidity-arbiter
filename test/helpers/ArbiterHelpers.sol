// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IArbiter} from "../../contracts/interfaces/IArbiter.sol";

abstract contract ArbiterHelpers is Test {
    function setDataFeed(IArbiter arbiter, address token, address dataFeed) public {
        address[] memory tokens = new address[](1);
        address[] memory dataFeeds = new address[](1);
        tokens[0] = token;
        dataFeeds[0] = dataFeed;
        arbiter.setDataFeeds(tokens, dataFeeds);
    }

    function test() public {}
}
