// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {AlgebraAdapter} from "../../../contracts/adapters/AlgebraAdapter.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {IWETH} from "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import {ERC20} from "../../mocks/ERC20Mock.sol";
import "forge-std/console.sol";

contract AlgebraAdapterIntegrationTest is Test {
    AlgebraAdapter adapter;
    IWETH WETH = IWETH(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address governor = makeAddr("governor");
    address algebraFactory = address(0x411b0fAcC3489691f28ad58c47006AF5E3Ab3A28);
    address algebraQuoter = address(0x2E0A046481c676235B806Bd004C4b492C850fb34);
    address USDC = address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);

    function setUp() public {
        vm.createSelectFork("https://rpc.ankr.com/polygon");
        adapter = new AlgebraAdapter(governor, "AlgebraAdapter 1.0");
        vm.prank(governor);
        adapter.addFactory(algebraFactory, algebraQuoter);
    }

    function testIntegration__AlgebraAdapter_getMaxOutput() public {
        (uint256 maxOutput, bytes memory extraArgs) = adapter.getMaxOutput(address(WETH), USDC, 1 ether);
        (address factory) = abi.decode(extraArgs, (address));
        assertTrue(maxOutput > 0);
        assertEq(factory, algebraFactory);
        (uint256 amountOut) = adapter.getOutputFromArgs(address(WETH), USDC, 1 ether, extraArgs);
        assertEq(maxOutput, amountOut);
    }

    function testIntegration__AlgebraAdapter_swap() public {
        (uint256 maxOutput, bytes memory extraArgs) = adapter.getMaxOutput(address(WETH), USDC, 1 ether);
        uint256 balanceBefore = ERC20(USDC).balanceOf(msg.sender);
        WETH.deposit{value: 1 ether}();
        ERC20(address(WETH)).approve(address(adapter), 1 ether);
        adapter.swap(address(WETH), USDC, msg.sender, 1 ether, maxOutput, extraArgs);
        assertEq(ERC20(USDC).balanceOf(msg.sender) - balanceBefore, maxOutput);
    }
}
