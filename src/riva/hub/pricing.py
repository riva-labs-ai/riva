"""Claude model list prices, used to estimate USD cost from token counts.

Source: https://platform.claude.com/docs/en/about-claude/pricing (checked
2026-09-27). Prices are base input / output per million tokens; cache reads,
cache writes and batch discounts are not modelled, so the estimate is an
upper bound for cached workloads. Update this table when Anthropic changes
pricing. Non-Claude models (Codex, Gemini, ...) are not priced and cost 0.

Model IDs are matched by longest prefix, so a dated variant such as
``claude-opus-4-5-20251101`` picks up the ``claude-opus-4-5`` row.
"""

from __future__ import annotations

# (input $/MTok, output $/MTok)
MODEL_PRICING: dict[str, tuple[float, float]] = {
    # Fable / Mythos
    "claude-fable-5-1": (10.0, 50.0),
    "claude-mythos-5-1": (10.0, 50.0),
    "claude-fable-5": (10.0, 50.0),
    "claude-mythos-5": (10.0, 50.0),
    # Opus
    "claude-opus-5-5": (4.0, 20.0),
    "claude-opus-5": (5.0, 25.0),
    "claude-opus-4-8": (5.0, 25.0),
    "claude-opus-4-7": (5.0, 25.0),
    "claude-opus-4-6": (5.0, 25.0),
    "claude-opus-4-5": (5.0, 25.0),
    "claude-opus-4-1": (15.0, 75.0),
    "claude-opus-4": (15.0, 75.0),
    # Sonnet
    "claude-sonnet-5": (2.0, 10.0),
    "claude-sonnet-4-6": (3.0, 15.0),
    "claude-sonnet-4-5": (3.0, 15.0),
    "claude-sonnet-4": (3.0, 15.0),
    "claude-3-7-sonnet": (3.0, 15.0),
    "claude-3-5-sonnet": (3.0, 15.0),
    # Haiku
    "claude-haiku-4-5": (1.0, 5.0),
    "claude-3-5-haiku": (0.80, 4.0),
}

# Longest IDs first so "claude-opus-4-5-..." never falls through to "claude-opus-4".
_BY_LENGTH: list[tuple[str, tuple[float, float]]] = sorted(
    MODEL_PRICING.items(), key=lambda kv: len(kv[0]), reverse=True
)


def lookup_prices(model_id: str) -> tuple[float, float] | None:
    """Return (input, output) $/MTok for a model ID, or None if unknown."""
    key = (model_id or "").strip().lower()
    if not key:
        return None
    exact = MODEL_PRICING.get(key)
    if exact is not None:
        return exact
    for known, prices in _BY_LENGTH:
        # Prefix must end at a separator so "claude-opus-4" doesn't match "claude-opus-45".
        if key.startswith(known) and (len(key) == len(known) or key[len(known)] in "-@:"):
            return prices
    return None


def estimate_cost_usd(model_id: str, input_tokens: int, output_tokens: int) -> float:
    """Estimated USD cost for a model + token pair; 0.0 for unknown models."""
    prices = lookup_prices(model_id)
    if prices is None:
        return 0.0
    input_price, output_price = prices
    return (max(input_tokens, 0) * input_price + max(output_tokens, 0) * output_price) / 1_000_000
