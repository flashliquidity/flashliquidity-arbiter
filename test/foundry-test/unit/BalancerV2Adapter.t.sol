// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {BalancerV2Adapter} from "../../../contracts/adapters/BalancerV2Adapter.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {BalancerV2VaultMock} from "../../mocks/BalancerV2VaultMock.sol";
import {BalancerV2PoolMock} from "../../mocks/BalancerV2PoolMock.sol";

contract BalancerV2AdapterTest is Test {
    BalancerV2Adapter adapter;
    address governor = makeAddr("governor");
    address bob = makeAddr("bob");
    address alice = makeAddr("alice");
    address rob = makeAddr("rob");
    BalancerV2VaultMock vault0;
    BalancerV2VaultMock vault1;
    BalancerV2PoolMock pool0;
    BalancerV2PoolMock pool1;
    address token0 = makeAddr("token0");
    address token1 = makeAddr("token1");
    address token2 = makeAddr("token2");

    function setUp() public {
        adapter = new BalancerV2Adapter(governor, "BalancerV2Adapter 1.0");
        address[] memory pool0Tokens = new address[](2);
        address[] memory pool1Tokens = new address[](3);
        pool0Tokens[0] = token0;
        pool0Tokens[1] = token1;
        pool1Tokens[0] = token0;
        pool1Tokens[1] = token1;
        pool1Tokens[2] = token2;
        vault0 = new BalancerV2VaultMock();
        vault1 = new BalancerV2VaultMock();
        pool0 = new BalancerV2PoolMock("pool0");
        pool1 = new BalancerV2PoolMock("pool1");
        vault0.addPool("pool0", pool0Tokens);
        vault0.addPool("pool1", pool1Tokens);
    }

    function test__BalancerV2Adapter_addVault() public {
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        adapter.addVault(address(vault0));
        vm.startPrank(governor);
        adapter.addVault(address(vault0));
        vm.expectRevert(BalancerV2Adapter.BalancerV2Adapter__VaultAlreadyRegistered.selector);
        adapter.addVault(address(vault0));
        vm.stopPrank();
    }

    function test__BalancerV2Adapter_removeVault() public {
        vm.startPrank(governor);
        adapter.addVault(address(vault0));
        adapter.addVault(address(vault1));
        vm.stopPrank();
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        adapter.removeVault(0);
        vm.prank(governor);
        adapter.removeVault(0);
        assertTrue(adapter.getVaultAtIndex(0) == address(vault1));
    }

    function test__BalancerV2Adapter_addVaultPools() public {
        address[] memory pools = new address[](2);
        pools[0] = address(pool0);
        pools[1] = address(pool1);
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        adapter.addVaultPools(address(vault0), pools);
        vm.prank(governor);
        adapter.addVaultPools(address(vault0), pools);
        address[] memory registeredPools = adapter.getVaultPools(address(vault0), token0, token1);
        assertTrue(registeredPools.length == 2);
        assertTrue(registeredPools[0] == address(pool0) && registeredPools[1] == address(pool1));
    }

    function test__BalancerV2Adapter_removeVaultPools() public {
        address[] memory pools = new address[](2);
        pools[0] = address(pool0);
        pools[1] = address(pool1);
        vm.prank(governor);
        adapter.addVaultPools(address(vault0), pools);
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        adapter.removeVaultPools(address(vault0), pools);
        vm.prank(governor);
        adapter.removeVaultPools(address(vault0), pools);
        address[] memory registeredPools = adapter.getVaultPools(address(vault0), token0, token1);
        assertTrue(registeredPools.length == 0);
    }
}
