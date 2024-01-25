// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import {ITSwapPool} from "../interfaces/ITSwapPool.sol";
import {IPoolFactory} from "../interfaces/IPoolFactory.sol";
// @todo @audit follow best practices and add external imports at the top
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract OracleUpgradeable is Initializable {
    address private s_poolFactory;

    function __Oracle_init(
        address poolFactoryAddress
    ) internal onlyInitializing {
        __Oracle_init_unchained(poolFactoryAddress);
    }

    function __Oracle_init_unchained(
        address poolFactoryAddress
    ) internal onlyInitializing {
        // @todo @audit add check for zero address
        s_poolFactory = poolFactoryAddress;
    }

    // @todo @audit price manipulation is possible here
    // @todo @audit use forked tests for live and deployed contracts
    function getPriceInWeth(address token) public view returns (uint256) {
        // @todo @audit add check for token zero address
        address swapPoolOfToken = IPoolFactory(s_poolFactory).getPool(token);
        return ITSwapPool(swapPoolOfToken).getPriceOfOnePoolTokenInWeth();
    }

    // @todo @audit no need for this function as getPriceInWeth is public
    function getPrice(address token) external view returns (uint256) {
        return getPriceInWeth(token);
    }

    function getPoolFactoryAddress() external view returns (address) {
        return s_poolFactory;
    }
}
