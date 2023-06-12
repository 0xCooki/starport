pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import "./Validator.sol";
import "forge-std/console.sol";

contract UniqueValidator is Validator {
  error InvalidLoan();

  constructor(
    LoanManager LM_,
    ConduitControllerInterface CI_,
    address strategist_,
    uint256 fee_
  ) Validator(LM_, CI_, strategist_, fee_) {}

  struct Details {
    address validator;
    address trigger; // isLoanHealthy
    address resolver; // liquidationMethod
    address pricing; // getOwed
    uint256 deadline;
    SpentItem collateral;
    ReceivedItem debt;
    bytes pricingData;
    bytes resolverData;
    bytes triggerData;
  }

  function validate(
    LoanManager.Loan calldata loan,
    bytes calldata nlrDetails,
    Signature calldata signature
  ) external view override returns (Response memory response) {
    if (msg.sender != address(LM)) {
      revert InvalidCaller();
    }

    Details memory details = _decodeLoanDetails(nlrDetails);

    _validateExecution(details, loan, nlrDetails, signature);

    //the recipient is the lender since we reuse the struct
    return
      Response({lender: details.debt.recipient, conduit: address(conduit)});
  }

  function _decodeLoanDetails(
    bytes calldata nlrDetails
  ) internal view returns (Details memory details) {
    details = abi.decode(nlrDetails, (Details));

    if (address(this) != details.validator) {
      revert InvalidValidator();
    }
    if (block.timestamp > details.deadline) {
      revert InvalidDeadline();
    }

    return details;
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
      loan.validator != address(this) ||
      loan.trigger != details.trigger ||
      loan.resolver != details.resolver ||
      loan.pricing != details.pricing ||
      keccak256(details.pricingData) != keccak256(details.pricingData) ||
      keccak256(details.resolverData) != keccak256(details.resolverData) ||
      keccak256(details.triggerData) != keccak256(details.triggerData)
    ) {
      revert InvalidLoan();
    }

    _validateSignature(
      keccak256(encodeWithAccountCounter(strategist, nlrDetails)),
      signature
    );
  }
}