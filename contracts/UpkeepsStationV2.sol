//SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AutomationRegistryInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationRegistryInterface1_2.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {KeeperRegistryWithdrawInterface} from "./interfaces/KeeperRegistryWithdrawInterface.sol";
import {IUpkeepsStationV2} from "./interfaces/IUpkeepsStationV2.sol";
import {BastionConnector} from "./types/BastionConnector.sol";
import {UpkeepsManager} from "./types/UpkeepsManager.sol";

struct UpkeepData {
    uint256 id;
    uint256 lastTimestamp;
}

contract UpkeepsStationV2 is
    IUpkeepsStationV2,
    BastionConnector,
    UpkeepsManager,
    AutomationCompatibleInterface
{
    using SafeERC20 for IERC20;

    address public immutable arbiter;
    UpkeepData[] public upkeeps;
    uint256[] public canceledUpkeeps;
    uint256 public stationUpkeepId;
    uint256 public retardNextRefuel = 6 hours;
    uint96 public minUpkeepBalance = 1e18;
    uint96 public toUpkeepAmount = 2e18;

    constructor(
        address _governor,
        address _arbiter,
        address _bastion,
        address _iLink,
        address _iRegistry,
        address _registrar,
        uint256 _transferGovernanceDelay
    )
        BastionConnector(_governor, _bastion, _transferGovernanceDelay)
        UpkeepsManager(_registrar, _iLink, _iRegistry)
    {
        arbiter = _arbiter;
    }

    function setMinUpkeepBalance(uint96 _minUpkeepBalance) external onlyGovernor {
        minUpkeepBalance = _minUpkeepBalance;
    }

    function setToUpkeepAmount(uint96 _toUpkeepAmount) external onlyGovernor {
        toUpkeepAmount = _toUpkeepAmount;
    }

    function initialize(uint96 _amount) external onlyGovernor {
        stationUpkeepId = registerUpkeep(
            "UpkeepsStationV2",
            address(this),
            1000000,
            address(this),
            new bytes(0),
            _amount,
            0,
            address(this)
        );
    }

    function selfDismantle() external onlyGovernor {
        iRegistry.cancelUpkeep(stationUpkeepId);
    }

    function withdrawStationUpkeep() external onlyGovernor {
        KeeperRegistryWithdrawInterface(address(iRegistry)).withdrawFunds(
            stationUpkeepId,
            address(this)
        );
    }

    function doesUpkeepNeedFunds(uint256 _index) private view returns (bool needFunds) {
        UpkeepData memory _upkeep = upkeeps[_index];
        if (block.timestamp - _upkeep.lastTimestamp > retardNextRefuel) {
            (, , , uint96 _balance, , , , ) = iRegistry.getUpkeep(_upkeep.id);
            if (_balance <= minUpkeepBalance) return true;
        }
        return false;
    }

    function addUpkeep(uint96 _amount) external onlyGovernor {
        uint256 _lastIndex = upkeeps.length;
        uint256 _newUpkeepId = registerUpkeep(
            string.concat("ArbiterUpkeep", Strings.toString(_lastIndex)),
            arbiter,
            1000000,
            address(this),
            abi.encode(_lastIndex),
            _amount,
            0,
            address(this)
        );
        upkeeps.push(UpkeepData(_newUpkeepId, block.timestamp));
    }

    function removeUpkeep() external onlyGovernor {
        uint256 _upkeepId = upkeeps[upkeeps.length - 1].id;
        canceledUpkeeps.push(_upkeepId);
        upkeeps.pop();
        iRegistry.cancelUpkeep(_upkeepId);
    }

    function withdrawCanceledUpkeeps(uint256 _upkeepsNumber) external onlyGovernor {
        uint256 _canceledToWithdrawLength = canceledUpkeeps.length;
        if (_upkeepsNumber >= _canceledToWithdrawLength) {
            revert OutOfBound();
        }
        uint256 _index = _upkeepsNumber == 0 ? _canceledToWithdrawLength : _upkeepsNumber;
        do {
            unchecked {
                _index--;
            }
            KeeperRegistryWithdrawInterface(address(iRegistry)).withdrawFunds(
                canceledUpkeeps[_index],
                address(this)
            );
            canceledUpkeeps.pop();
        } while (_index > 0);
    }

    function checkUpkeep(
        bytes calldata
    ) external view override returns (bool upkeepNeeded, bytes memory performData) {
        uint256 _linkBalance = iLink.balanceOf(address(this));
        if (_linkBalance < toUpkeepAmount) {
            return (false, new bytes(0));
        }
        (, , , uint96 _stationBalance, , , , ) = iRegistry.getUpkeep(stationUpkeepId);
        if (_stationBalance <= minUpkeepBalance) {
            upkeepNeeded = true;
            performData = abi.encode(uint32(0), uint256(0));
        } else {
            uint256 _upkeepsLength = upkeeps.length;
            for (uint256 i = 0; i < _upkeepsLength; ) {
                if (doesUpkeepNeedFunds(i)) {
                    return (true, abi.encode(uint32(1), i));
                }
                unchecked {
                    i++;
                }
            }
        }
    }

    function performUpkeep(bytes calldata performData) external override {
        (uint32 _mode, uint256 _upkeepIndex) = abi.decode(performData, (uint32, uint256));
        uint256 _amount = toUpkeepAmount;
        if (_mode == 0) {
            (, , , uint96 _stationBalance, , , , ) = iRegistry.getUpkeep(stationUpkeepId);
            if (_stationBalance > minUpkeepBalance) {
                revert RefuelNotNeeded();
            }
            iLink.approve(address(iRegistry), _amount);
            iRegistry.addFunds(stationUpkeepId, uint96(_amount));
        } else if (_mode == 1) {
            uint256 _upkeepId = upkeeps[_upkeepIndex].id;
            (, , , uint96 _upkeepBalance, , , , ) = iRegistry.getUpkeep(_upkeepId);
            if (_upkeepBalance > minUpkeepBalance) {
                revert RefuelNotNeeded();
            }
            iLink.approve(address(iRegistry), _amount);
            iRegistry.addFunds(_upkeepId, uint96(_amount));
        } else {
            revert InvalidPerformData();
        }
    }
}
