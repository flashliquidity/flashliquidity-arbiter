// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAlgebraFactory {
    function poolByPair(address, address) external view returns (address);
}
