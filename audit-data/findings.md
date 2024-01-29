### [H-1] Incorrect `updateExchangeRate` usage in `ThunderLoan:deposit` causes protocol to think it has more fees than it actually does, which blocks redemption of funds and incorrect exchange rate calculation

**Description:** In the ThunderLoan system, the `exchangeRate` is responsible for calculating the exchange rate between asset tokens and underlying tokens. In a way, it's responsible for keeping track of how many fees to give to liquidity providers.
However, the `deposit` function in the `ThunderLoan` contract uses the `updateExchangeRate` function incorrectly as it updates the exchange rate without collecting fees.

```javascript
    function deposit(
        IERC20 token,
        uint256 amount
    ) external revertIfZero(amount) revertIfNotAllowedToken(token) {
        AssetToken assetToken = s_tokenToAssetToken[token];
        uint256 exchangeRate = assetToken.getExchangeRate();
        uint256 mintAmount = (amount * assetToken.EXCHANGE_RATE_PRECISION()) /
            exchangeRate;
        emit Deposit(msg.sender, token, amount);

        assetToken.mint(msg.sender, mintAmount);

        uint256 calculatedFee = getCalculatedFee(token, amount);
@>      assetToken.updateExchangeRate(calculatedFee);

        token.safeTransferFrom(msg.sender, address(assetToken), amount);
    }
```

**Impact:**

**Proof of Concept:**

**Recommended Mitigation:**
