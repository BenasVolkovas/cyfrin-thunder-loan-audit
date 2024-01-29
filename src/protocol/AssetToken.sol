// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AssetToken is ERC20 {
    // @todo @audit keep naming consistent (start with Capital letter after underscore)
    error AssetToken__onlyThunderLoan();
    error AssetToken__ExhangeRateCanOnlyIncrease(
        uint256 oldExchangeRate,
        uint256 newExchangeRate
    );
    error AssetToken__ZeroAddress();

    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    // @note underlying is the token that is deposited into the pool (USDC)
    IERC20 private immutable i_underlying;
    address private immutable i_thunderLoan;

    // The underlying per asset exchange rate
    // ie: s_exchangeRate = 2
    // means 1 asset token is worth 2 underlying tokens
    // @note underlying == USDC
    // @note asset token == shares of the pool
    uint256 private s_exchangeRate;
    uint256 public constant EXCHANGE_RATE_PRECISION = 1e18;
    uint256 private constant STARTING_EXCHANGE_RATE = 1e18;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event ExchangeRateUpdated(uint256 newExchangeRate);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyThunderLoan() {
        if (msg.sender != i_thunderLoan) {
            revert AssetToken__onlyThunderLoan();
        }
        _;
    }

    modifier revertIfZeroAddress(address someAddress) {
        if (someAddress == address(0)) {
            revert AssetToken__ZeroAddress();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    // @question-answered where are the tokens stored?
    // @answer they are stored in asset token contract

    constructor(
        address thunderLoan,
        IERC20 underlying,
        string memory assetName,
        string memory assetSymbol
    )
        ERC20(assetName, assetSymbol)
        revertIfZeroAddress(thunderLoan)
        revertIfZeroAddress(address(underlying))
    {
        i_thunderLoan = thunderLoan;
        i_underlying = underlying;
        s_exchangeRate = STARTING_EXCHANGE_RATE;
    }

    // @note thunder loan will call this function to mint asset tokens
    function mint(address to, uint256 amount) external onlyThunderLoan {
        _mint(to, amount);
    }

    // @note thunder loan will call this function to burn asset tokens
    function burn(address account, uint256 amount) external onlyThunderLoan {
        _burn(account, amount);
    }

    function transferUnderlyingTo(
        address to,
        uint256 amount
    ) external onlyThunderLoan {
        // @todo @audit USDC can blacklist this contract and prevent it from sending USDC
        // @note USDC has 6 decimals
        i_underlying.safeTransfer(to, amount);
    }

    function updateExchangeRate(uint256 fee) external onlyThunderLoan {
        // 1. Get the current exchange rate
        // 2. How big the fee is should be divided by the total supply
        // 3. So if the fee is 1e18, and the total supply is 2e18, the exchange rate be multiplied by 1.5
        // if the fee is 0.5 ETH, and the total supply is 4, the exchange rate should be multiplied by 1.125
        // it should always go up, never down @note INVARIANT to follow
        // newExchangeRate = oldExchangeRate * (totalSupply + fee) / totalSupply
        // newExchangeRate = 1 (4 + 0.5) / 4
        // newExchangeRate = 1.125
        // @todo @audit too many storage reads
        // @question-answered what if the fee or supply is 0?
        // @answer supply won't be zero as we mint asset tokens before calling this function
        // @answer if fee is zero, exchange rate will stay the same as no fee is charged
        // @note 1e18 * (100e18 + 0.6e18) / 100e18 = 1e18 * 100.6e18 / 100e18 = 1e18 * 1.006 = 1.006
        uint256 newExchangeRate = (s_exchangeRate * (totalSupply() + fee)) /
            totalSupply();

        if (newExchangeRate <= s_exchangeRate) {
            revert AssetToken__ExhangeRateCanOnlyIncrease(
                s_exchangeRate,
                newExchangeRate
            );
        }
        s_exchangeRate = newExchangeRate;
        emit ExchangeRateUpdated(s_exchangeRate);
    }

    function getExchangeRate() external view returns (uint256) {
        return s_exchangeRate;
    }

    function getUnderlying() external view returns (IERC20) {
        return i_underlying;
    }
}
