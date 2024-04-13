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
    ERC20Mock linkToken;
    ERC20Mock mockToken;
    FlashLiquidityPairMock pairMock;
    address governor = makeAddr("governor");
    address verifierProxy;
    address feeManager;
    address bob = makeAddr("bob");
    address alice = makeAddr("alice");
    address rob = makeAddr("rob");
    address forwarder = makeAddr("forwarder");
    uint256 supply = 1e9 ether;
    uint32 priceMaxStaleness = 60;
    uint64 minLinkDataStreams = 1e17;

    function setUp() public {
        vm.prank(governor);
        linkToken = new ERC20Mock("LINK", "LINK", supply);
        mockToken = new ERC20Mock("MOCK", "MOCK", supply);
        feeManager = address(new FeeManagerMock(address(linkToken)));
        verifierProxy = address(new VerifierProxyMock(feeManager));
        pairMock = new FlashLiquidityPairMock(address(linkToken), address(mockToken), governor);
        arbiter = new Arbiter(governor, verifierProxy, address(linkToken), priceMaxStaleness, minLinkDataStreams);
    }

    function test__Arbiter_setPriceMaxStaleness() public {
        uint32 newPriceMaxStaleness = 420;
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        arbiter.setPriceMaxStaleness(newPriceMaxStaleness);
        assertNotEq(arbiter.getPriceMaxStaleness(), newPriceMaxStaleness);
        vm.prank(governor);
        arbiter.setPriceMaxStaleness(newPriceMaxStaleness);
        assertEq(arbiter.getPriceMaxStaleness(), newPriceMaxStaleness);
    }

    function test__Arbiter_setMinLinkDataStreams() public {
        uint64 newMinLinkDataStreams = 1e18;
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        arbiter.setMinLinkDataStreams(newMinLinkDataStreams);
        assertNotEq(arbiter.getMinLinkDataStreams(), newMinLinkDataStreams);
        vm.prank(governor);
        arbiter.setMinLinkDataStreams(newMinLinkDataStreams);
        assertEq(arbiter.getMinLinkDataStreams(), newMinLinkDataStreams);
    }

    function test__Arbiter_setVerifier() public {
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        arbiter.setVerifierProxy(alice);
        assertNotEq(arbiter.getVerifierProxy(), alice);
        vm.prank(governor);
        arbiter.setVerifierProxy(alice);
        assertEq(arbiter.getVerifierProxy(), alice);
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
        assertNotEq(arbiter.getDataFeed(tokens[0]), dataFeeds[0]);
        assertNotEq(arbiter.getDataFeed(tokens[1]), dataFeeds[1]);
        vm.prank(governor);
        arbiter.setDataFeeds(tokens, dataFeeds);
        assertEq(arbiter.getDataFeed(tokens[0]), dataFeeds[0]);
        assertEq(arbiter.getDataFeed(tokens[1]), dataFeeds[1]);
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
        feedIDs[0] = "feedID0";
        feedIDs[1] = "feedID1";
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        arbiter.setDataStreams(tokens, feedIDs);
        assertNotEq(
            keccak256(abi.encodePacked(arbiter.getDataStream(tokens[0]))), keccak256(abi.encodePacked(feedIDs[0]))
        );
        assertNotEq(
            keccak256(abi.encodePacked(arbiter.getDataStream(tokens[1]))), keccak256(abi.encodePacked(feedIDs[1]))
        );
        vm.prank(governor);
        arbiter.setDataStreams(tokens, feedIDs);
        assertEq(keccak256(abi.encodePacked(arbiter.getDataStream(tokens[0]))), keccak256(abi.encodePacked(feedIDs[0])));
        assertEq(keccak256(abi.encodePacked(arbiter.getDataStream(tokens[1]))), keccak256(abi.encodePacked(feedIDs[1])));
        tokens = new address[](1);
        vm.prank(governor);
        vm.expectRevert(Arbiter.Arbiter__InconsistentParamsLength.selector);
        arbiter.setDataStreams(tokens, feedIDs);
    }

    function test__Arbiter_setArbiterJob() public {
        uint96 reserveToMinProfitRatio = 1000;
        uint96 reserveToTriggerProfitRatio = 1050;
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        arbiter.setArbiterJob(
            address(pairMock), governor, forwarder, reserveToMinProfitRatio, reserveToTriggerProfitRatio, 0, 0
        );
        vm.startPrank(governor);
        vm.expectRevert(Arbiter.Arbiter__NotManager.selector);
        arbiter.setArbiterJob(
            address(pairMock), governor, forwarder, reserveToMinProfitRatio, reserveToTriggerProfitRatio, 0, 0
        );
        pairMock.setManager(address(arbiter));
        vm.expectRevert(Arbiter.Arbiter__DataFeedNotSet.selector);
        arbiter.setArbiterJob(
            address(pairMock), governor, forwarder, reserveToMinProfitRatio, reserveToTriggerProfitRatio, 0, 0
        );
        setDataFeed(arbiter, address(linkToken), bob);
        setDataFeed(arbiter, address(mockToken), rob);
        vm.expectRevert(Arbiter.Arbiter__InvalidProfitToReservesRatio.selector);
        arbiter.setArbiterJob(address(pairMock), governor, forwarder, reserveToMinProfitRatio, 1112, 0, 0);
        arbiter.setArbiterJob(
            address(pairMock), governor, forwarder, reserveToMinProfitRatio, reserveToTriggerProfitRatio, 0, 0
        );
        (
            address rewardVault,
            uint96 jobMinProfitRatio,
            address automationForwarder,
            uint96 jobTriggerProfitRatio,
            address token0,
            uint8 token0Decimals,
            address token1,
            uint8 token1Decimals
        ) = arbiter.getJobConfig(address(pairMock));
        assertEq(rewardVault, governor);
        assertEq(jobMinProfitRatio, reserveToMinProfitRatio);
        assertEq(automationForwarder, forwarder);
        assertEq(jobTriggerProfitRatio, reserveToTriggerProfitRatio);
        assertEq(token0, address(linkToken));
        assertEq(token1, address(mockToken));
        assertEq(token0Decimals, linkToken.decimals());
        assertEq(token1Decimals, mockToken.decimals());
        arbiter.setArbiterJob(
            address(pairMock), governor, bob, reserveToMinProfitRatio, reserveToTriggerProfitRatio, 8, 0
        );
        (
            rewardVault,
            jobMinProfitRatio,
            automationForwarder,
            jobTriggerProfitRatio,
            token0,
            token0Decimals,
            token1,
            token1Decimals
        ) = arbiter.getJobConfig(address(pairMock));
        assertEq(token0Decimals, 8);
        assertEq(token1Decimals, mockToken.decimals());
        vm.stopPrank();
    }

    function test__Arbiter_deleteArbiterJob() public {
        vm.startPrank(governor);
        pairMock.setManager(address(arbiter));
        setDataFeed(arbiter, address(linkToken), bob);
        setDataFeed(arbiter, address(mockToken), rob);
        arbiter.setArbiterJob(address(pairMock), governor, forwarder, 420, 420, 0, 0);
        vm.stopPrank();
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        arbiter.deleteArbiterJob(address(pairMock));
        vm.prank(governor);
        arbiter.deleteArbiterJob(address(pairMock));
        (
            address rewardVault,
            uint96 jobMinProfitUSD,
            address automationForwarder,
            uint96 jobTriggerProfitUSD,
            address token0,
            uint8 token0Decimals,
            address token1,
            uint8 token1Decimals
        ) = arbiter.getJobConfig(address(pairMock));
        assertEq(rewardVault, address(0));
        assertEq(jobMinProfitUSD, uint96(0));
        assertEq(automationForwarder, address(0));
        assertEq(jobTriggerProfitUSD, uint96(0));
        assertEq(token0, address(0));
        assertEq(token1, address(0));
        assertEq(token0Decimals, uint8(0));
        assertEq(token1Decimals, uint8(0));
    }

    function test__Arbiter_pushDexAdapter() public {
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        arbiter.pushDexAdapter(bob);
        vm.prank(governor);
        arbiter.pushDexAdapter(bob);
        assertEq(arbiter.getDexAdapter(0), bob);
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
        assertEq(arbiter.getDexAdapter(0), rob);
        vm.expectRevert(Arbiter.Arbiter__OutOfBound.selector);
        arbiter.removeDexAdapter(1);
        arbiter.removeDexAdapter(0);
        vm.expectRevert();
        arbiter.getDexAdapter(0);
    }

    function test__Arbiter__performUpkeepRevertIfNotForwarder() public {
        vm.startPrank(governor);
        pairMock.setManager(address(arbiter));
        setDataFeed(arbiter, address(linkToken), bob);
        setDataFeed(arbiter, address(mockToken), rob);
        arbiter.setArbiterJob(address(pairMock), governor, forwarder, 1000, 1000, 0, 0);
        vm.stopPrank();
        Arbiter.ArbiterCall memory call;
        call.selfBalancingPool = address(pairMock);
        vm.expectRevert(Arbiter.Arbiter__NotFromForwarder.selector);
        arbiter.performUpkeep(abi.encode(new bytes[](0), call));
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
        assertEq(linkToken.balanceOf(address(arbiter)), 1 ether);
        assertEq(linkToken.balanceOf(bob), 0);
        arbiter.recoverERC20(bob, tokens, amounts);
        assertEq(linkToken.balanceOf(address(arbiter)), 0);
        assertEq(linkToken.balanceOf(bob), 1 ether);
        vm.stopPrank();
    }
}
