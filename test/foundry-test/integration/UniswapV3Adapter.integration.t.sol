// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {UniswapV3Adapter} from "../../../contracts/adapters/UniswapV3Adapter.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {IWETH} from "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import {ERC20} from "../../mocks/ERC20Mock.sol";

contract UniswapV3IntegrationAdapterTest is Test {
    UniswapV3Adapter adapter;
    uint256 arbitrumFork;
    address governor = makeAddr("governor");
    address uniV3Factory = address(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    address uniV3Quoter = address(0xc80f61d1bdAbD8f5285117e1558fDDf8C64870FE);
    uint24[] uniV3Fees = [500, 3000];
    IWETH WETH = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address USDC = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);

    function setUp() public {
        arbitrumFork = vm.createSelectFork("https://arb1.arbitrum.io/rpc");
        adapter = new UniswapV3Adapter(governor, "UniswapV3Adapter 1.0");
        vm.prank(governor);
        adapter.addFactory(uniV3Factory, uniV3Quoter, uniV3Fees);
    }

    function testIntegration__UniswapV3Adapter_getMaxOutput() public {
        (uint256 maxOutput, bytes memory extraArgs) = adapter.getMaxOutput(address(WETH), USDC, 1 ether);
        (address factory, uint24 fee) = abi.decode(extraArgs, (address, uint24));
        assertTrue(maxOutput > 0 && factory == uniV3Factory);
        assertTrue(fee == uniV3Fees[0] || fee == uniV3Fees[1]);
    }

    function testIntegration__UniswapV3Adapter_swap() public {
        (uint256 maxOutput, bytes memory extraArgs) = adapter.getMaxOutput(address(WETH), USDC, 1 ether);
        assertFalse(ERC20(USDC).balanceOf(msg.sender) > 0);
        WETH.deposit{value: 1 ether}();
        ERC20(address(WETH)).approve(address(adapter), 1 ether);
        adapter.swap(address(WETH), USDC, msg.sender, 1 ether, maxOutput, extraArgs);
        assertTrue(ERC20(USDC).balanceOf(msg.sender) == maxOutput);
    }
}
