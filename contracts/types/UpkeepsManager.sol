//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AutomationRegistryInterface, State, Config} from "@chainlink/contracts/src/v0.8/interfaces/AutomationRegistryInterface1_2.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {KeeperRegistrarInterface} from "../interfaces/KeeperRegistrarInterface.sol";

abstract contract UpkeepsManager {
    address public immutable registrar;
    LinkTokenInterface public immutable iLink;
    AutomationRegistryInterface public immutable iRegistry;

    error AutoApprovalDisabled();

    constructor(address _registrar, address _linkToken, address _keeperRegistry) {
        registrar = _registrar;
        iLink = LinkTokenInterface(_linkToken);
        iRegistry = AutomationRegistryInterface(_keeperRegistry);
    }

    function registerUpkeep(
        string memory _name,
        address _upkeepContract,
        uint32 _gasLimit,
        address _adminAddress,
        bytes memory _checkData,
        uint96 _amount,
        uint8 _source,
        address _sender
    ) internal returns (uint256 _upkeepID) {
        (State memory _state, Config memory _c, address[] memory _k) = iRegistry.getState();
        uint256 _oldNonce = _state.nonce;

        bytes memory payload = abi.encode(
            _name,
            new bytes(0),
            _upkeepContract,
            _gasLimit,
            _adminAddress,
            _checkData,
            _amount,
            _source,
            _sender
        );

        iLink.transferAndCall(
            registrar,
            _amount,
            bytes.concat(KeeperRegistrarInterface.register.selector, payload)
        );
        (_state, _c, _k) = iRegistry.getState();
        if (_state.nonce == _oldNonce + 1) {
            _upkeepID = uint256(
                keccak256(
                    abi.encodePacked(
                        blockhash(block.number - 1),
                        address(iRegistry),
                        uint32(_oldNonce)
                    )
                )
            );
        } else {
            revert AutoApprovalDisabled();
        }
    }
}
