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
        string memory name,
        address upkeepContract,
        uint32 gasLimit,
        address adminAddress,
        bytes memory checkData,
        uint96 amount,
        uint8 source,
        address sender
    ) internal returns (uint256 upkeepID) {
        (State memory state, Config memory _c, address[] memory _k) = iRegistry.getState();
        uint256 oldNonce = state.nonce;

        bytes memory payload = abi.encode(
            name,
            new bytes(0),
            upkeepContract,
            gasLimit,
            adminAddress,
            checkData,
            amount,
            source,
            sender
        );

        iLink.transferAndCall(
            registrar,
            amount,
            bytes.concat(KeeperRegistrarInterface.register.selector, payload)
        );
        (state, _c, _k) = iRegistry.getState();
        uint256 newNonce = state.nonce;
        if (newNonce == oldNonce + 1) {
            upkeepID = uint256(
                keccak256(
                    abi.encodePacked(
                        blockhash(block.number - 1),
                        address(iRegistry),
                        uint32(oldNonce)
                    )
                )
            );
        } else {
            revert AutoApprovalDisabled();
        }
    }
}
