// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {UniswapV2Adapter} from "../../../contracts/adapters/UniswapV2Adapter.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {IWETH} from "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import {ERC20} from "../../mocks/ERC20Mock.sol";

contract UniswapV2AdapterIntegrationTest is Test {
    UniswapV2Adapter adapter;
    uint256 arbitrumFork;
    address uniV2ForkFactory = address(0xd394E9CC20f43d2651293756F8D320668E850F1b);
    address governor = makeAddr("governor");
    IWETH WETH = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address USDC = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);

    function setUp() public {
        arbitrumFork = vm.createSelectFork("https://arb1.arbitrum.io/rpc");
        adapter = new UniswapV2Adapter(governor, "UniswapV2Adapter 1.0");
        vm.prank(governor);
        adapter.addFactory(uniV2ForkFactory, 997, 1000);
    }

    function testIntegration__UniswapV2Adapter_getMaxOutput() public {
        (uint256 maxOutput, bytes memory extraArgs) = adapter.getMaxOutput(address(WETH), USDC, 1000000000);
        assertTrue(maxOutput > 0 && abi.decode(extraArgs, (address)) == uniV2ForkFactory);
    }

    function testIntegration__UniswapV2Adapter_swap() public {
        (uint256 maxOutput, bytes memory extraArgs) = adapter.getMaxOutput(address(WETH), USDC, 1 ether);
        assertFalse(ERC20(USDC).balanceOf(msg.sender) > 0);
        WETH.deposit{value: 1 ether}();
        ERC20(address(WETH)).approve(address(adapter), 1 ether);
        adapter.swap(address(WETH), USDC, msg.sender, 1 ether, maxOutput, extraArgs);
        assertTrue(ERC20(USDC).balanceOf(msg.sender) == maxOutput);
    }
}
