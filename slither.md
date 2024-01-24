slither . --config-file slither.config.json --checklist 
**THIS CHECKLIST IS NOT COMPLETE**. Use `--show-ignored-findings` to show all the results.
Summary
 - [unused-return](#unused-return) (1 results) (Medium)
 - [events-maths](#events-maths) (1 results) (Low)
 - [reentrancy-benign](#reentrancy-benign) (2 results) (Low)
 - [reentrancy-events](#reentrancy-events) (1 results) (Low)
## unused-return
Impact: Medium
Confidence: Medium
 - [ ] ID-0
[ThunderLoan.flashloan(address,IERC20,uint256,bytes)](src/protocol/ThunderLoan.sol#L211-L261) ignores return value by [receiverAddress.functionCall(abi.encodeCall(IFlashLoanReceiver.executeOperation,(address(token),amount,fee,msg.sender,params)))](src/protocol/ThunderLoan.sol#L240-L251)

src/protocol/ThunderLoan.sol#L211-L261


## events-maths
Impact: Low
Confidence: Medium
 - [ ] ID-1
[ThunderLoan.updateFlashLoanFee(uint256)](src/protocol/ThunderLoan.sol#L315-L321) should emit an event for: 
	- [s_flashLoanFee = newFee](src/protocol/ThunderLoan.sol#L319) 

src/protocol/ThunderLoan.sol#L315-L321


## reentrancy-benign
Impact: Low
Confidence: Medium
 - [ ] ID-2
Reentrancy in [ThunderLoan.flashloan(address,IERC20,uint256,bytes)](src/protocol/ThunderLoan.sol#L211-L261):
	External calls:
	- [assetToken.updateExchangeRate(fee)](src/protocol/ThunderLoan.sol#L231)
	- [assetToken.transferUnderlyingTo(receiverAddress,amount)](src/protocol/ThunderLoan.sol#L237)
	- [receiverAddress.functionCall(abi.encodeCall(IFlashLoanReceiver.executeOperation,(address(token),amount,fee,msg.sender,params)))](src/protocol/ThunderLoan.sol#L240-L251)
	State variables written after the call(s):
	- [s_currentlyFlashLoaning[token] = false](src/protocol/ThunderLoan.sol#L260)

src/protocol/ThunderLoan.sol#L211-L261


 - [ ] ID-3
Reentrancy in [ThunderLoan.flashloan(address,IERC20,uint256,bytes)](src/protocol/ThunderLoan.sol#L211-L261):
	External calls:
	- [assetToken.updateExchangeRate(fee)](src/protocol/ThunderLoan.sol#L231)
	State variables written after the call(s):
	- [s_currentlyFlashLoaning[token] = true](src/protocol/ThunderLoan.sol#L235)

src/protocol/ThunderLoan.sol#L211-L261


## reentrancy-events
Impact: Low
Confidence: Medium
 - [ ] ID-4
Reentrancy in [ThunderLoan.flashloan(address,IERC20,uint256,bytes)](src/protocol/ThunderLoan.sol#L211-L261):
	External calls:
	- [assetToken.updateExchangeRate(fee)](src/protocol/ThunderLoan.sol#L231)
	Event emitted after the call(s):
	- [FlashLoan(receiverAddress,token,amount,fee,params)](src/protocol/ThunderLoan.sol#L233)

src/protocol/ThunderLoan.sol#L211-L261


