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

contract ArbiterFuzzTest is Test, ArbiterHelpers {
    Arbiter arbiter;
    address governor = makeAddr("governor");
    address verifierProxy;
    address feeManager;
    address adapter = makeAddr("adapter");
    address linkToken = makeAddr("linkToken");

    function setUp() public {
        feeManager = address(new FeeManagerMock(address(linkToken)));
        verifierProxy = address(new VerifierProxyMock(feeManager));
        arbiter = new Arbiter(governor, verifierProxy, address(linkToken), 60, 1e17);
        vm.prank(governor);
        arbiter.pushDexAdapter(adapter);
    }

    function testFuzz__Arbiter_gettersCantRevert(address token, address selfBalancingPool, uint256 adapterIndex)
        public
        view
    {
        adapterIndex = bound(adapterIndex, 0, arbiter.allAdaptersLength() - 1);
        arbiter.getDataFeed(token);
        arbiter.getDataStream(token);
        arbiter.getDexAdapter(adapterIndex);
        arbiter.getJobConfig(selfBalancingPool);
        arbiter.getPriceMaxStaleness();
        arbiter.getVerifierProxy();
    }
}
