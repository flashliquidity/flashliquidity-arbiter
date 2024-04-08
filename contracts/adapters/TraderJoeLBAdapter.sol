//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILBFactory} from "../interfaces/ILBFactory.sol";
import {ILBPair} from "../interfaces/ILBPair.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {DexAdapter} from "./DexAdapter.sol";

/**
 * @title TraderJoeLBAdapter
 * @author Oddcod3 (@oddcod3)
 */
contract TraderJoeLBAdapter is DexAdapter, Governable {
    using SafeERC20 for IERC20;

    error TraderJoeLBAdapter__InvalidPool();
    error TraderJoeLBAdapter__InsufficientOutput();
    error TraderJoeLBAdapter__NotRegisteredFactory();
    error TraderJoeLBAdapter__FactoryAlreadyRegistered();
    error TraderJoeLBAdapter__OutOfBound();

    /// @dev Array of Liquidity Book Factory interfaces that the contract interacts with.
    ILBFactory[] private s_factories;
    /// @dev Mapping to track registration status of each factory.
    mapping(address factory => bool isRegistered) private s_isRegisteredFactory;

    constructor(address governor, string memory description) DexAdapter(description) Governable(governor) {}

    /**
     * @dev Registers a new factory in the adapter. This function can only be called by the contract's governor.
     * @param factory The address of the Liquidity Book factory to be registered.
     * @notice This function will revert with 'TraderJoeLBAdapter__FactoryAlreadyRegistered' if the factory is already registered.
     */
    function addFactory(address factory) external onlyGovernor {
        if (s_isRegisteredFactory[factory]) revert TraderJoeLBAdapter__FactoryAlreadyRegistered();
        s_isRegisteredFactory[factory] = true;
        s_factories.push(ILBFactory(factory));
    }

    /**
     * @dev Removes a factory from the list. This function can only be called by the contract's governor.
     * @param factoryIndex The index of the factory in the s_factories array to be removed.
     * @notice If the factoryIndex is out of bounds of s_factories array, the function will revert with 'TraderJoeLBAdapter__OutOfBound'.
     * @notice Care must be taken to pass the correct factoryIndex, as an incorrect index can result in the removal of the wrong factory.
     */
    function removeFactory(uint256 factoryIndex) external onlyGovernor {
        uint256 factoriesLen = s_factories.length;
        if (factoriesLen == 0 || factoryIndex >= factoriesLen) revert TraderJoeLBAdapter__OutOfBound();
        s_isRegisteredFactory[address(s_factories[factoryIndex])] = false;
        if (factoryIndex < factoriesLen - 1) {
            s_factories[factoryIndex] = s_factories[factoriesLen - 1];
        }
        s_factories.pop();
    }

    /// @inheritdoc DexAdapter
    function _swap(
        address tokenIn,
        address tokenOut,
        address to,
        uint256 amountIn,
        uint256 amountOutMin,
        bytes memory extraArgs
    ) internal override {
        (address factory, uint24 binStep) = abi.decode(extraArgs, (address, uint24));
        if (!s_isRegisteredFactory[factory]) revert TraderJoeLBAdapter__NotRegisteredFactory();
        ILBFactory.LBPairInformation memory pairInfo =
            ILBFactory(factory).getLBPairInformation(IERC20(tokenIn), IERC20(tokenOut), binStep);
        if (pairInfo.LBPair == address(0)) revert TraderJoeLBAdapter__InvalidPool();
        bool swapForY = ILBPair(pairInfo.LBPair).getTokenY() == tokenOut;
        IERC20(tokenIn).safeTransferFrom(msg.sender, pairInfo.LBPair, amountIn);
        bytes32 amountsOut = ILBPair(pairInfo.LBPair).swap(swapForY, to);
        uint256 amountOut;
        assembly {
            switch swapForY
            case 0 { amountOut := and(amountsOut, 0xffffffffffffffffffffffffffffffff) }
            default { amountOut := shr(128, amountsOut) }
        }
        if (amountOut < amountOutMin) revert TraderJoeLBAdapter__InsufficientOutput();
    }

    /// @inheritdoc DexAdapter
    function _getMaxOutput(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        view
        override
        returns (uint256 maxOutput, bytes memory extraArgs)
    {
        ILBFactory targetFactory;
        ILBPair targetPair;
        uint256 tempOutput;
        uint256 lbPairsLen;
        uint256 factoriesLen = s_factories.length;
        ILBFactory.LBPairInformation[] memory lbPairs;
        for (uint256 i; i < factoriesLen;) {
            targetFactory = s_factories[i];
            lbPairs = targetFactory.getAllLBPairs(tokenIn, tokenOut);
            lbPairsLen = lbPairs.length;
            for (uint256 j; j < lbPairsLen;) {
                targetPair = ILBPair(lbPairs[j].LBPair);
                tempOutput = _getAmountOut(targetPair, amountIn, targetPair.getTokenY() == tokenOut);
                if (tempOutput > maxOutput) {
                    maxOutput = tempOutput;
                    extraArgs = abi.encode(address(targetFactory), lbPairs[j].binStep);
                }
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc DexAdapter
    function _getOutputFromArgs(address tokenIn, address tokenOut, uint256 amountIn, bytes memory extraArgs)
        internal
        view
        override
        returns (uint256 amountOut)
    {
        (address factory, uint24 binStep) = abi.decode(extraArgs, (address, uint24));
        if (!s_isRegisteredFactory[factory]) return 0;
        ILBFactory.LBPairInformation memory pairInfo =
            ILBFactory(factory).getLBPairInformation(IERC20(tokenIn), IERC20(tokenOut), binStep);
        ILBPair pair = ILBPair(pairInfo.LBPair);
        bool swapForY = pair.getTokenY() == tokenOut;
        return _getAmountOut(pair, amountIn, swapForY);
    }

    /**
     * @dev Calculates the expected output token amount for a given input amount in a swap.
     * @param pair The ILBPair of the pair contract from the Liquidity Book.
     * @param amountIn The quantity of the input token that is being swapped.
     * @param swapForY Boolean indicating whether the swap is for token Y (true) or token X (false).
     * @return amountOut The calculated amount of the output token expected from the swap.
     */
    function _getAmountOut(ILBPair pair, uint256 amountIn, bool swapForY) private view returns (uint256 amountOut) {
        try pair.getSwapOut(uint128(amountIn), swapForY) returns (uint128 amountInLeft, uint128 amountOutValue, uint128)
        {
            if (amountInLeft == 0) amountOut = amountOutValue;
        } catch {}
    }

    /**
     * @dev Retrieves the address of a specific factory, identified by its index.
     * @param factoryIndex The index of the factory in the 's_factories' array.
     * @return factory The address of the factory at the specified index.
     * @notice The function will return the address of the factory.
     *         It is important to ensure that the factoryIndex is within the bounds of the array to avoid out-of-bounds errors.
     */
    function getFactoryAtIndex(uint256 factoryIndex) external view returns (address factory) {
        factory = address(s_factories[factoryIndex]);
    }
}
