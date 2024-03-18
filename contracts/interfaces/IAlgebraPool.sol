// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAlgebraPool {
    function swap(
        address recipient,
        bool zeroToOne,
        int256 amountSpecified,
        uint160 limitSqrtPrice,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}
