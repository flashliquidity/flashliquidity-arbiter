// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {BalancerV2Adapter} from "../../../contracts/adapters/BalancerV2Adapter.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {IWETH} from "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import {ERC20} from "../../mocks/ERC20Mock.sol";

contract BalancerV2AdapterIntegrationTest is Test {
    BalancerV2Adapter adapter;
    IWETH WETH = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address governor = makeAddr("governor");
    address balancerV2Vault = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    address balancerQuoter = address(0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5);
    address wbtcWethUsdcPool = address(0x64541216bAFFFEec8ea535BB71Fbc927831d0595);
    address wstEthWethPool = address(0x9791d590788598535278552EEcD4b211bFc790CB);
    address WBTC = address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);

    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc");
        adapter = new BalancerV2Adapter(governor, "BalancerV2Adapter 1.0");
        address[] memory pools = new address[](1);
        pools[0] = wbtcWethUsdcPool;
        vm.startPrank(governor);
        adapter.addVault(balancerV2Vault);
        adapter.addVaultPools(balancerV2Vault, pools);
        vm.stopPrank();
    }

    function testIntegration__BalancerV2Adapter_getMaxOutput() public {
        (uint256 maxOutput, bytes memory extraArgs) = adapter.getMaxOutput(address(WETH), WBTC, 1 ether);
        (address vault, uint256 poolIndex) = abi.decode(extraArgs, (address, uint256));
        assertTrue(maxOutput > 0);
        assertEq(vault, balancerV2Vault);
        assertEq(poolIndex, 0);
        (uint256 amountOut) = adapter.getOutputFromArgs(address(WETH), WBTC, 1 ether, extraArgs);
        assertEq(maxOutput, amountOut);
    }

    function testIntegration__BalancerV2Adapter_swap() public {
        (uint256 maxOutput, bytes memory extraArgs) = adapter.getMaxOutput(address(WETH), WBTC, 1 ether);
        assertFalse(ERC20(WBTC).balanceOf(msg.sender) > 0);
        WETH.deposit{value: 1 ether}();
        ERC20(address(WETH)).approve(address(adapter), 1 ether);
        adapter.swap(address(WETH), WBTC, msg.sender, 1 ether, maxOutput, extraArgs);
        assertEq(ERC20(WBTC).balanceOf(msg.sender), maxOutput);
    }
}
