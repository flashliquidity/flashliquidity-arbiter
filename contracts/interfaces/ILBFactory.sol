// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILBFactory {
    struct LBPairInformation {
        uint24 binStep;
        address LBPair;
        bool createdByOwner;
        bool ignoredForRouting;
    }

    function getAllLBPairs(address tokenX, address tokenY)
        external
        view
        returns (LBPairInformation[] memory LBPairsBinStep);

    function getLBPairInformation(IERC20 tokenX, IERC20 tokenY, uint256 binStep)
        external
        view
        returns (LBPairInformation memory);
}
