// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Arbiter} from "../../../contracts/Arbiter.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {ERC20} from "../../mocks/ERC20Mock.sol";
import {IFlashLiquidityFactory} from "../../../contracts/interfaces/IFlashLiquidityFactory.sol";
import {ArbiterHelpers} from "../../helpers/ArbiterHelpers.sol";
import {UniswapV2Adapter} from "../../../contracts/adapters/UniswapV2Adapter.sol";
import {UniswapV3Adapter} from "../../../contracts/adapters/UniswapV3Adapter.sol";

contract ArbiterIntegrationTest is Test, ArbiterHelpers {
    Arbiter arbiter;
    UniswapV2Adapter uniV2Adapter;
    UniswapV3Adapter uniV3Adapter;
    IUniswapV2Router02 flRouter = IUniswapV2Router02(0xaf5990f587f4e10aE0361f657712F9B1067e25b3);
    uint256 arbitrumFork;
    address governor = address(0x95E05C9870718cb171C04080FDd186571475027E);
    address verifierProxy = address(0x478Aa2aC9F6D65F84e09D9185d126c3a17c2a93C);
    address bob = makeAddr("bob");
    address rewardVault = makeAddr("rewardVault");
    address linkToken = makeAddr("linkToken");

    address flFactory = address(0x6e553d5f028bD747a27E138FA3109570081A23aE);
    address uniV3Factory = address(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    address uniV3Quoter = address(0xc80f61d1bdAbD8f5285117e1558fDDf8C64870FE);
    address uniV3ForkFactory = address(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    address uniV2ForkFactory = address(0xd394E9CC20f43d2651293756F8D320668E850F1b);
    uint24[] uniV3Fees = [500, 3000];
    address flEthUsdc = address(0xdE67c936D87455A77BAeF8Ab7e6c26Eb3D828735);
    address ETH = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address USDC = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address ethFeed = address(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);
    address usdcFeed = address(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3);

    uint32 priceMaxStaleness = 86400;

    function setUp() public {
        arbitrumFork = vm.createSelectFork("https://arb1.arbitrum.io/rpc");
        arbiter = new Arbiter(governor, verifierProxy, linkToken, priceMaxStaleness);
        uniV2Adapter = new UniswapV2Adapter(governor, "UniswapV2 Adapter 0.0.1");
        uniV3Adapter = new UniswapV3Adapter(governor, "UniswapV3 Adapter 0.0.1");
        vm.startPrank(governor);
        arbiter.pushDexAdapter(address(uniV2Adapter));
        arbiter.pushDexAdapter(address(uniV3Adapter));
        setDataFeed(arbiter, ETH, ethFeed);
        setDataFeed(arbiter, USDC, usdcFeed);
        IFlashLiquidityFactory(flFactory).setPairManager(flEthUsdc, address(arbiter));
        arbiter.setArbiterJob(flEthUsdc, rewardVault, 0, 0, 0);
        uniV2Adapter.addFactory(uniV2ForkFactory, 997, 1000);
        uniV3Adapter.addFactory(uniV3Factory, uniV3Quoter, uniV3Fees);
        vm.stopPrank();
    }

    function testIntegration__Arbiter_performUpkeep() public {
        (bool upkeepNeeded, bytes memory performData) = arbiter.checkUpkeep(abi.encode(flEthUsdc));
        if(!upkeepNeeded) {
            /// swap until rebalancing is needed
            address[] memory path = new address[](2);
            path[0] = ETH;
            path[1] = USDC;
            vm.prank(governor);
            IFlashLiquidityFactory(flFactory).setPairManager(flEthUsdc, address(0));
            while (!upkeepNeeded) {
                flRouter.swapExactETHForTokens{value: 1e16}(1, path, governor, block.timestamp);
                (upkeepNeeded, performData) = arbiter.checkUpkeep(abi.encode(flEthUsdc));
            }
            vm.prank(governor);
            IFlashLiquidityFactory(flFactory).setPairManager(flEthUsdc, address(arbiter));
        }
        uint256 balance0 = ERC20(ETH).balanceOf(rewardVault);
        uint256 balance1 = ERC20(USDC).balanceOf(rewardVault);
        assertFalse(balance0 > 0 || balance1 > 0);
        arbiter.performUpkeep(performData);
        balance0 = ERC20(ETH).balanceOf(rewardVault);
        balance1 = ERC20(USDC).balanceOf(rewardVault);
        assertTrue(balance0 > 0 || balance1 > 0);
    }
}
