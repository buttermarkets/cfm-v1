// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin-contracts-5.0.2/token/ERC20/IERC20.sol";
import "./QuestionTypes.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IMarket.sol";
import "../ConditionalTokens.sol";

contract ConditionalScalarMarket is IMarket {
    string public marketName;
    uint256[2] public outcomes;

    IOracle public immutable oracle;
    ConditionalTokens public immutable conditionalTokens;

    ScalarQuestion question;

    bool public isResolved;

    constructor(IOracle _oracle, ConditionalTokens _conditionalTokens, ScalarQuestion memory _question) {
        oracle = _oracle;
        conditionalTokens = _conditionalTokens;

        question = _question;
        outcomes[0] = _question.lowerBound;
        outcomes[1] = _question.upperBound;

        conditionalTokens.prepareCondition(
            address(oracle), keccak256(abi.encodePacked(oracle.encodeScalarQuestion(_question.text))), outcomes.length
        );
    }

    function resolve() external {
        revert("not implemented yet");
    }

    function getResolved() public view returns (bool) {
        return isResolved;
    }
}
