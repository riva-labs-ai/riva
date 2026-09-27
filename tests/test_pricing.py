"""Cost estimation from the Claude price table."""

import pytest

from riva.hub import link
from riva.hub.pricing import MODEL_PRICING, estimate_cost_usd, lookup_prices


def test_exact_and_dated_ids_resolve_to_the_same_row():
    assert lookup_prices("claude-opus-4-5") == (5.0, 25.0)
    assert lookup_prices("claude-opus-4-5-20251101") == (5.0, 25.0)
    assert lookup_prices("Claude-Sonnet-4-5-20250929 ") == (3.0, 15.0)
    # Vertex-style version separator.
    assert lookup_prices("claude-opus-4-5@20251101") == (5.0, 25.0)


def test_longest_prefix_wins():
    # "claude-opus-4" and "claude-opus-4-5" are both rows; the dated 4.5 ID must
    # not fall through to the (three times pricier) Opus 4 row.
    assert lookup_prices("claude-opus-4-5-20251101") != lookup_prices("claude-opus-4-20250514")
    assert lookup_prices("claude-opus-4-20250514") == (15.0, 75.0)
    # And a prefix must end at a separator.
    assert lookup_prices("claude-opus-45") is None


def test_legacy_three_x_ids():
    assert lookup_prices("claude-3-5-sonnet-20241022") == (3.0, 15.0)
    assert lookup_prices("claude-3-5-haiku-20241022") == (0.80, 4.0)


def test_unknown_and_non_claude_models_cost_nothing():
    assert lookup_prices("gpt-5") is None
    assert lookup_prices("gemini-2.5-pro") is None
    assert lookup_prices("") is None
    assert estimate_cost_usd("gpt-5", 1_000_000, 1_000_000) == 0.0
    assert estimate_cost_usd("", 10, 10) == 0.0


@pytest.mark.parametrize(
    "model, inp, out, expected",
    [
        ("claude-opus-5", 1_000_000, 1_000_000, 30.0),
        ("claude-sonnet-5", 500_000, 100_000, 2.0),
        ("claude-haiku-4-5", 2_000_000, 0, 2.0),
        ("claude-fable-5-1", 100_000, 10_000, 1.5),
    ],
)
def test_cost_arithmetic(model, inp, out, expected):
    assert estimate_cost_usd(model, inp, out) == pytest.approx(expected)


def test_negative_token_counts_are_clamped():
    assert estimate_cost_usd("claude-opus-5", -5, -5) == 0.0


def test_table_is_well_formed():
    for model, (inp, out) in MODEL_PRICING.items():
        assert model == model.lower().strip()
        assert 0 < inp < out


def test_machine_name_rejects_hex_hostnames(monkeypatch):
    monkeypatch.setattr(link.socket, "gethostname", lambda: "ac077525cc8f")
    monkeypatch.setattr(link.platform, "node", lambda: "")
    monkeypatch.setattr("riva.hub.config.get_client_id", lambda: "0123456789abcdef")
    assert link._machine_name() == "01234567"


def test_machine_name_strips_local_suffix(monkeypatch):
    monkeypatch.setattr(link.socket, "gethostname", lambda: "Saurabhs-MacBook-Pro.local")
    assert link._machine_name() == "Saurabhs-MacBook-Pro"
