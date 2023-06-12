pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import "src/originators/Originator.sol";

contract UniqueOriginator is Originator {
  error InvalidLoan();

  constructor(
    LoanManager LM_,
    ConduitControllerInterface CI_,
    address strategist_,
    uint256 fee_
  ) Originator(LM_, CI_, strategist_, fee_) {}

  struct Details {
    address originator;
    address hook; // isLoanHealthy
    address handler; // liquidationMethod
    address pricing; // getOwed
    uint256 deadline;
    SpentItem collateral;
    ReceivedItem debt;
    bytes pricingData;
    bytes handlerData;
    bytes hookData;
  }

  function validate(
    LoanManager.Loan calldata loan,
    bytes calldata nlrDetails,
    Signature calldata signature
  ) external view override returns (Response memory response) {
    if (msg.sender != address(LM)) {
      revert InvalidCaller();
    }

    if (address(this) != loan.originator) {
      revert InvalidValidator();
    }

    Details memory details = abi.decode(nlrDetails, (Details));
    if (block.timestamp > details.deadline) {
      revert InvalidDeadline();
    }

    _validateExecution(details, loan, nlrDetails, signature);

    //the recipient is the lender since we reuse the struct
    return
      Response({lender: details.debt.recipient, conduit: address(conduit)});
  }

  function _validateExecution(
    Details memory details,
    LoanManager.Loan calldata loan,
    bytes calldata nlrDetails,
    Signature calldata signature
  ) internal view {
    if (
      details.debt.token != loan.debt.token ||
      details.debt.identifier != loan.debt.identifier ||
      details.debt.itemType != loan.debt.itemType ||
      loan.debt.amount > details.debt.amount ||
      loan.debt.amount == 0
    ) {
      revert InvalidDebtToken();
    }

    if (
      loan.originator != address(this) ||
      loan.hook != details.hook ||
      loan.handler != details.handler ||
      loan.pricing != details.pricing ||
      keccak256(loan.pricingData) != keccak256(details.pricingData) ||
      keccak256(details.handlerData) != keccak256(details.handlerData) ||
      keccak256(details.hookData) != keccak256(details.hookData)
    ) {
      revert InvalidLoan();
    }

    _validateSignature(
      keccak256(encodeWithAccountCounter(strategist, nlrDetails)),
      signature
    );
  }
}
