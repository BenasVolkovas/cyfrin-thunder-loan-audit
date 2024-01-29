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

**Impact:** There are several impacts of this bug:

1. The `ThunderLoan::redeem` function is blocked from redeeming the total liquidity provider balance, because the protocol wants to transfer more than it should.
2. Rewards are calculated incorrectly, leading to liquidity providers getting more rewards than they should.

**Proof of Concept:**

1. LP deposits
2. User takes out a flash loan
3. LP tries to redeem their funds
4. The redeem function reverts

Place the following into `ThunderLoan.t.sol`:

```javascript
function test_audit_RedeemsAfterLoan() public setAllowedToken hasDeposits {
    uint256 amountToBorrow = AMOUNT * 10;
    uint256 calculatedFee = thunderLoan.getCalculatedFee(
        tokenA,
        amountToBorrow
    );

    vm.startPrank(user);
    tokenA.mint(address(mockFlashLoanReceiver), calculatedFee);
    thunderLoan.flashloan(
        address(mockFlashLoanReceiver),
        tokenA,
        amountToBorrow,
        ""
    );
    vm.stopPrank();

    uint256 amountToRedeem = type(uint256).max;

    vm.startPrank(liquidityProvider);
    thunderLoan.redeem(tokenA, amountToRedeem);
    vm.stopPrank();
}
```

**Recommended Mitigation:** Remove the incorrectly used `updateExchangeRate` function call from the `deposit` function.

```diff
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

-       uint256 calculatedFee = getCalculatedFee(token, amount);
-       assetToken.updateExchangeRate(calculatedFee);

        token.safeTransferFrom(msg.sender, address(assetToken), amount);
    }
```
