// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

enum QuestionType {
    Categorical,
    MultiCategorical,
    Scalar
}

struct MultiCategoricalQuestion {
    string text;
    string[] outcomes;
}

struct ScalarQuestion {
    string text;
    uint256 lowerBound;
    uint256 upperBound;
}
