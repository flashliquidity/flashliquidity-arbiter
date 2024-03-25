// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TraderJoeLBAdapter} from "../../../contracts/adapters/TraderJoeLBAdapter.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {IWETH} from "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import {ERC20} from "../../mocks/ERC20Mock.sol";

contract TraderJoeLBAdapterIntegrationTest is Test {
    TraderJoeLBAdapter adapter;
    IWETH WETH = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address governor = makeAddr("governor");
    address lbFactory = address(0x8e42f2F4101563bF679975178e880FD87d3eFd4e);
    address USDC = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);

    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc");
        adapter = new TraderJoeLBAdapter(governor, "TraderJoeLBAdapter 1.0");
        vm.prank(governor);
        adapter.addFactory(lbFactory);
    }

    function testIntegration__TraderJoeLBAdapter_getMaxOutput() public {
        (uint256 maxOutput, bytes memory extraArgs) = adapter.getMaxOutput(address(WETH), USDC, 1 ether);
        (address factory) = abi.decode(extraArgs, (address));
        assertTrue(maxOutput > 0);
        assertEq(factory, lbFactory);
    }

    function testIntegration__TraderJoeLBAdapter_swap() public {
        (uint256 maxOutput, bytes memory extraArgs) = adapter.getMaxOutput(address(WETH), USDC, 1 ether);
        uint256 balanceBefore = ERC20(USDC).balanceOf(msg.sender);
        WETH.deposit{value: 1 ether}();
        ERC20(address(WETH)).approve(address(adapter), 1 ether);
        adapter.swap(address(WETH), USDC, msg.sender, 1 ether, maxOutput, extraArgs);
        assertEq(ERC20(USDC).balanceOf(msg.sender) - balanceBefore, maxOutput);
    }
}
