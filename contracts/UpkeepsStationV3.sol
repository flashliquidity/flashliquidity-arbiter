//SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AutomationRegistryInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationRegistryInterface1_2.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {KeeperRegistryWithdrawInterface} from "./interfaces/KeeperRegistryWithdrawInterface.sol";
import {IUpkeepsStationV3} from "./interfaces/IUpkeepsStationV3.sol";
import {BastionConnector} from "./types/BastionConnector.sol";
import {UpkeepsManager} from "./types/UpkeepsManager.sol";

struct UpkeepData {
    uint256 id;
    uint256 lastTimestamp;
}

contract UpkeepsStationV3 is
    IUpkeepsStationV3,
    BastionConnector,
    UpkeepsManager,
    AutomationCompatibleInterface
{
    using SafeERC20 for IERC20;

    address public immutable arbiter;
    UpkeepData[] public arbiterUpkeeps;
    UpkeepData[] public otherUpkeeps;
    uint256[] public canceledUpkeeps;
    uint256 public stationUpkeepId;
    uint256 public minDelayNextRefuel = 6 hours;
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

    function setMinDelayBetweenRefuel(uint256 _minDelayNextRefuel) external onlyGovernor {
        minDelayNextRefuel = _minDelayNextRefuel;
    }

    function initialize(uint96 _amount) external onlyGovernor {
        stationUpkeepId = registerUpkeep(
            "UpkeepsStationV3",
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

    function doesUpkeepNeedFunds(UpkeepData memory _upkeep) private view returns (bool) {
        if (block.timestamp - _upkeep.lastTimestamp > minDelayNextRefuel) {
            (, , , uint96 _balance, , , , ) = iRegistry.getUpkeep(_upkeep.id);
            if (_balance < minUpkeepBalance) return true;
        }
        return false;
    }

    function addArbiterUpkeep(uint96 _amount) external onlyGovernor {
        uint256 _lastIndex = arbiterUpkeeps.length;
        uint256 _newUpkeepId = registerUpkeep(
            string.concat("Arbiter: ", Strings.toString(_lastIndex)),
            arbiter,
            1000000,
            address(this),
            abi.encode(_lastIndex),
            _amount,
            0,
            address(this)
        );
        arbiterUpkeeps.push(UpkeepData(_newUpkeepId, block.timestamp));
    }

    function removeArbiterUpkeep() external onlyGovernor {
        uint256 _upkeepId = arbiterUpkeeps[arbiterUpkeeps.length - 1].id;
        canceledUpkeeps.push(_upkeepId);
        arbiterUpkeeps.pop();
        iRegistry.cancelUpkeep(_upkeepId);
    }

    function addUpkeep(
        string calldata _name,
        address _target,
        uint32 _gasLimit,
        bytes calldata _checkData,
        uint96 _amount
    ) external onlyGovernor {
        uint256 _newUpkeepId = registerUpkeep(
            _name,
            _target,
            _gasLimit,
            address(this),
            _checkData,
            _amount,
            0,
            address(this)
        );
        otherUpkeeps.push(UpkeepData(_newUpkeepId, block.timestamp));
    }

    function removeUpkeep(uint256 _index) external onlyGovernor {
        uint256 _lastIndex = otherUpkeeps.length - 1;
        uint256 _upkeepId = otherUpkeeps[_index].id;
        canceledUpkeeps.push(_upkeepId);
        if(_index < otherUpkeeps.length - 1) {
            otherUpkeeps[_index] = otherUpkeeps[_lastIndex];
        }
        otherUpkeeps.pop();
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
            return(true, abi.encode(uint32(0), uint256(0)));
        } else {
            UpkeepData memory _upkeep;
            uint256 _upkeepsLength = arbiterUpkeeps.length;
            for (uint256 i; i < _upkeepsLength; ) {
                _upkeep = arbiterUpkeeps[i];
                if (doesUpkeepNeedFunds(_upkeep)) {
                    return (true, abi.encode(uint32(1), i));
                }
                unchecked {
                    i++;
                }
            }
            _upkeepsLength = otherUpkeeps.length;
            for (uint256 i; i < _upkeepsLength; ) {
                _upkeep = otherUpkeeps[i];
                if (doesUpkeepNeedFunds(_upkeep)) {
                    return (true, abi.encode(uint32(2), i));
                }
                unchecked {
                    i++;
                }
            }
        }
    }

    function performUpkeep(bytes calldata _performData) external override {
        (uint32 _mode, uint256 _upkeepIndex) = abi.decode(_performData, (uint32, uint256));
        uint256 _amount = toUpkeepAmount;
        AutomationRegistryInterface _iRegistry = iRegistry; 
        if (_mode == 0) {
            uint256 _stationUpkeepId = stationUpkeepId;
            (, , , uint96 _stationBalance, , , , ) = _iRegistry.getUpkeep(_stationUpkeepId);
            if (_stationBalance > minUpkeepBalance) {
                revert RefuelNotNeeded();
            }
            iLink.approve(address(_iRegistry), _amount);
            _iRegistry.addFunds(_stationUpkeepId, uint96(_amount));
        } else if (_mode == 1 || _mode == 2) {
            UpkeepData memory _upkeep = _mode == 1 ? arbiterUpkeeps[_upkeepIndex] : otherUpkeeps[_upkeepIndex];
            if (!doesUpkeepNeedFunds(_upkeep)) {
                revert RefuelNotNeeded();
            }
            iLink.approve(address(_iRegistry), _amount);
            _iRegistry.addFunds(_upkeep.id, uint96(_amount));
        } else {
            revert InvalidPerformData();
        }
    }
}
