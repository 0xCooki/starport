pragma solidity ^0.8.17;

import {Starport} from "starport-core/Starport.sol";

abstract contract Validation {
    /*
    * @dev Validates the loan against the module
    * @param loan The loan to validate
    * @return bytes4 The validation result
    */

    function validate(Starport.Loan calldata) external view virtual returns (bytes4);
}