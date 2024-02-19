// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Arbiter} from "../../../contracts/Arbiter.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {ERC20, ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {FeeManagerMock} from "../../mocks/FeeManagerMock.sol";
import {VerifierProxyMock} from "../../mocks/VerifierProxyMock.sol";
import {FlashLiquidityPairMock} from "../../mocks/FlashLiquidityPairMock.sol";
import {ArbiterHelpers} from "../../helpers/ArbiterHelpers.sol";

contract ArbiterTest is Test, ArbiterHelpers {
    Arbiter arbiter;
    address governor = makeAddr("governor");
    address verifierProxy;
    address feeManager;
    address bob = makeAddr("bob");
    address alice = makeAddr("alice");
    address rob = makeAddr("rob");

    ERC20Mock linkToken;
    ERC20Mock mockToken;
    FlashLiquidityPairMock pairMock;
    uint256 supply = 1e9 ether;
    uint32 priceMaxStaleness = 60;

    function setUp() public {
        vm.prank(governor);
        linkToken = new ERC20Mock("LINK","LINK", supply);
        mockToken = new ERC20Mock("MOCK","MOCK", supply);
        feeManager = address(new FeeManagerMock(address(linkToken)));
        verifierProxy = address(new VerifierProxyMock(feeManager));
        pairMock = new FlashLiquidityPairMock(address(linkToken), address(mockToken), governor);
        arbiter = new Arbiter(governor, verifierProxy, address(linkToken), priceMaxStaleness);
    }

    function test__Arbiter_setPriceMaxStaleness() public {
        uint32 newPriceMaxStaleness = 420;
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        arbiter.setPriceMaxStaleness(newPriceMaxStaleness);
        assertFalse(arbiter.getPriceMaxStaleness() == newPriceMaxStaleness);
        vm.prank(governor);
        arbiter.setPriceMaxStaleness(newPriceMaxStaleness);
        assertTrue(arbiter.getPriceMaxStaleness() == newPriceMaxStaleness);
    }

    function test__Arbiter_setVerifier() public {
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        arbiter.setVerifierProxy(alice);
        assertFalse(arbiter.getVerifierProxy() == alice);
        vm.prank(governor);
        arbiter.setVerifierProxy(alice);
        assertTrue(arbiter.getVerifierProxy() == alice);
    }

    function test__Arbiter_setDataFeeds() public {
        address[] memory tokens = new address[](2);
        address[] memory dataFeeds = new address[](2);
        tokens[0] = address(linkToken);
        tokens[1] = alice;
        dataFeeds[0] = rob;
        dataFeeds[1] = bob;
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        arbiter.setDataFeeds(tokens, dataFeeds);
        assertFalse(arbiter.getDataFeed(tokens[0]) == dataFeeds[0]);
        assertFalse(arbiter.getDataFeed(tokens[1]) == dataFeeds[1]);
        vm.prank(governor);
        arbiter.setDataFeeds(tokens, dataFeeds);
        assertTrue(arbiter.getDataFeed(tokens[0]) == dataFeeds[0]);
        assertTrue(arbiter.getDataFeed(tokens[1]) == dataFeeds[1]);
        tokens = new address[](1);
        vm.prank(governor);
        vm.expectRevert(Arbiter.Arbiter__InconsistentParamsLength.selector);
        arbiter.setDataFeeds(tokens, dataFeeds);
    }

    function test__Arbiter_setDataStreams() public {
        address[] memory tokens = new address[](2);
        string[] memory feedIDs = new string[](2);
        tokens[0] = address(linkToken);
        tokens[1] = alice;
        feedIDs[0] = "wannacry?";
        feedIDs[1] = "wannadie?";
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        arbiter.setDataStreams(tokens, feedIDs);
        assertFalse(
            keccak256(abi.encodePacked(arbiter.getDataStream(tokens[0]))) == keccak256(abi.encodePacked(feedIDs[0]))
        );
        assertFalse(
            keccak256(abi.encodePacked(arbiter.getDataStream(tokens[1]))) == keccak256(abi.encodePacked(feedIDs[1]))
        );
        vm.prank(governor);
        arbiter.setDataStreams(tokens, feedIDs);
        assertTrue(
            keccak256(abi.encodePacked(arbiter.getDataStream(tokens[0]))) == keccak256(abi.encodePacked(feedIDs[0]))
        );
        assertTrue(
            keccak256(abi.encodePacked(arbiter.getDataStream(tokens[1]))) == keccak256(abi.encodePacked(feedIDs[1]))
        );
        tokens = new address[](1);
        vm.prank(governor);
        vm.expectRevert(Arbiter.Arbiter__InconsistentParamsLength.selector);
        arbiter.setDataStreams(tokens, feedIDs);
    }

    function test__Arbiter_setArbiterJob() public {
        uint96 minProfitUSD = 1e8;
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        arbiter.setArbiterJob(address(pairMock), governor, minProfitUSD, 0, 0);
        vm.startPrank(governor);
        vm.expectRevert(Arbiter.Arbiter__NotManager.selector);
        arbiter.setArbiterJob(address(pairMock), governor, minProfitUSD, 0, 0);
        pairMock.setManager(address(arbiter));
        vm.expectRevert(Arbiter.Arbiter__DataFeedNotSet.selector);
        arbiter.setArbiterJob(address(pairMock), governor, minProfitUSD, 0, 0);
        setDataFeed(arbiter, address(linkToken), bob);
        setDataFeed(arbiter, address(mockToken), rob);
        arbiter.setArbiterJob(address(pairMock), governor, minProfitUSD, 0, 0);
        (
            address rewardVault,
            uint96 jobMinProfitUSD,
            address token0,
            address token1,
            uint8 token0Decimals,
            uint8 token1Decimals
        ) = arbiter.getJobConfig(address(pairMock));
        assertTrue(rewardVault == governor);
        assertTrue(jobMinProfitUSD == minProfitUSD);
        assertTrue(token0 == address(linkToken) && token1 == address(mockToken));
        assertTrue(token0Decimals == linkToken.decimals() && token1Decimals == mockToken.decimals());
        arbiter.setArbiterJob(address(pairMock), governor, minProfitUSD, 8, 0);
        (rewardVault, jobMinProfitUSD, token0, token1, token0Decimals, token1Decimals) =
            arbiter.getJobConfig(address(pairMock));
        assertTrue(token0Decimals == 8 && token1Decimals == mockToken.decimals());
        vm.stopPrank();
    }

    function test__Arbiter_deleteArbiterJob() public {
        vm.startPrank(governor);
        pairMock.setManager(address(arbiter));
        setDataFeed(arbiter, address(linkToken), bob);
        setDataFeed(arbiter, address(mockToken), rob);
        arbiter.setArbiterJob(address(pairMock), governor, 420, 0, 0);
        vm.stopPrank();
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        arbiter.deleteArbiterJob(address(pairMock));
        vm.prank(governor);
        arbiter.deleteArbiterJob(address(pairMock));
        (
            address rewardVault,
            uint96 jobMinProfitUSD,
            address token0,
            address token1,
            uint8 token0Decimals,
            uint8 token1Decimals
        ) = arbiter.getJobConfig(address(pairMock));
        assertTrue(rewardVault == address(0));
        assertTrue(jobMinProfitUSD == uint96(0));
        assertTrue(token0 == address(0) && token1 == address(0));
        assertTrue(token0Decimals == uint8(0) && token1Decimals == uint8(0));
    }

    function test__Arbiter_pushDexAdapter() public {
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        arbiter.pushDexAdapter(bob);
        vm.prank(governor);
        arbiter.pushDexAdapter(bob);
        assertTrue(arbiter.getDexAdapter(0) == bob);
    }

    function test__Arbiter_removeDexAdapter() public {
        vm.startPrank(governor);
        arbiter.pushDexAdapter(bob);
        arbiter.pushDexAdapter(rob);
        vm.stopPrank();
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        arbiter.removeDexAdapter(0);
        vm.startPrank(governor);
        arbiter.removeDexAdapter(0);
        assertTrue(arbiter.getDexAdapter(0) == rob);
        vm.expectRevert(Arbiter.Arbiter__OutOfBound.selector);
        arbiter.removeDexAdapter(1);
        arbiter.removeDexAdapter(0);
        vm.expectRevert();
        arbiter.getDexAdapter(0);
    }

    function test__Arbiter_recoverERC20() public {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(linkToken);
        amounts[0] = 1 ether;
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        arbiter.recoverERC20(bob, tokens, amounts);
        vm.startPrank(governor);
        linkToken.transfer(address(arbiter), 1 ether);
        assertTrue(linkToken.balanceOf(address(arbiter)) == 1 ether);
        assertTrue(linkToken.balanceOf(bob) == 0);
        arbiter.recoverERC20(bob, tokens, amounts);
        assertTrue(linkToken.balanceOf(address(arbiter)) == 0);
        assertTrue(linkToken.balanceOf(bob) == 1 ether);
        vm.stopPrank();
    }
}
