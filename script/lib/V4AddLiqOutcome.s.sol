// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "./V4AddLiqBase.s.sol";

/// @title V4AddLiqOutcome
/// @notice Uniswap v4 liquidity utilities for outcome<>collateral (IF<>USDC) pools.
/// @dev Inherits common utilities from V4AddLiqBase. Uses asymmetric deposit amounts
///      (ifPerPool vs collateralPerPool) and supports configurable price bands.
///      Semantic price: P = collateralToken / ifToken (numeraire/quoted)
abstract contract V4AddLiqOutcome is V4AddLiqBase {
    /// @notice Config for outcome<>collateral pools with asymmetric amounts and price band
    struct OutcomeCfg {
        BaseCfg base;
        uint256 minP1e18; // min price (numeraire/quoted), 0 for full range
        uint256 maxP1e18; // max price (numeraire/quoted), 0 for full range
        uint256 ifPerPool; // IF token amount per pool
        uint256 collateralPerPool; // Collateral amount per pool
    }

    // ===== Config parsing =====

    /// @notice Parse config from .ifPools section
    function _parseOutcomeCfg(string memory json) internal returns (OutcomeCfg memory cfg) {
        cfg.base = _parseBaseCfg(json);

        // Parse amounts from .ifPools
        cfg.ifPerPool = vm.parseJsonUint(json, ".ifPools.ifPerPool");
        cfg.collateralPerPool = vm.parseJsonUint(json, ".ifPools.collateralPerPool");
        require(cfg.ifPerPool > 0, "ifPerPool must be > 0");
        require(cfg.collateralPerPool > 0, "collateralPerPool must be > 0");

        // Parse optional price band from .ifPools.{minP1e18,maxP1e18}
        (cfg.minP1e18, cfg.maxP1e18) = _parseOptionalBand(json, ".ifPools.minP1e18", ".ifPools.maxP1e18");
    }

    // ===== High level helper =====

    /// @notice Mint a single outcome<>collateral pool with asymmetric amounts and price range
    /// @dev Wrapper around _mintSinglePoolSemantic with asymmetric amounts
    /// @param cfg Config with amounts and price band
    /// @param ifToken The wrapped outcome (IF) token (quoted)
    /// @param collateralToken The collateral token (numeraire)
    /// @param recipient LP token recipient
    /// @param deadline Transaction deadline
    function _mintSinglePoolAsymmetric(
        OutcomeCfg memory cfg,
        address ifToken,
        address collateralToken,
        address recipient,
        uint256 deadline
    ) internal {
        // Semantic: P = numeraire / quoted = collateralToken / ifToken
        _mintSinglePoolSemantic(
            cfg.base,
            ifToken, // tokenQuoted
            collateralToken, // tokenNumeraire
            cfg.minP1e18,
            cfg.maxP1e18,
            cfg.ifPerPool, // amountQuotedMax
            cfg.collateralPerPool, // amountNumeraireMax
            recipient,
            deadline
        );
    }
}
