"""Arsenal: ball catalog (out-of-box specs + normalized reaction) and recommendations."""
from .catalog import normalize, validate, Reaction, CATALOG_VERSION, NORMALIZER_VERSION
from .recommend import Condition, rank_for_condition, arsenal_gaps, target_for
from .configured import configured_reaction, parse_layout, as_rankable, ConfiguredReaction
