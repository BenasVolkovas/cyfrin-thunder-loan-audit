// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// @todo @audit this interface is not used anywhere
interface IThunderLoan {
    // @todo @audit this function takes address token, but contract uses IERC20 interface
    function repay(address token, uint256 amount) external;
}
