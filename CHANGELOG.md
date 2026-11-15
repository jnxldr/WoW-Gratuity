# Changelog

## 2.1.1
- Default message puts the tip amount first: "LF [Enchanting: ...], my mats, tipping 8c (10% of AH cost)". A template still
  set to an earlier default switches once; your own templates are kept.

## 2.1.0
- The advert message now posts the enchant as a **clickable link** (`[Enchanting: Enchant Boots - Minor Stamina]`): the
  default template uses `{link}`. A template still set to the old default switches once; your own templates are kept.
- `/gratuity dump` fills in `{link}` too; the settings explain `{link}` and `{enchant}`.

## 2.0.3
- First release on CurseForge and Wago.
- No changes in game. README: what Gratuity does, commands, and how it was made.

## 2.0.2
- Enchant Chest - Living Stats removed: its mats don't exist in Forever (179 enchants now).
- The full price check's summary tells mats the game doesn't know apart from mats the AH didn't answer for.

## 2.0.1
- Settings panel scrolls, so nothing is cut off when you have many chat channels; hint text is easier to read.
- The full price check's summary also names mats that weren't checked.

## 2.0.0
- **Own AH prices; Auctionator is now optional.** At the AH, Gratuity checks the selected enchant's mats by itself.
- **Check mat prices** button under the AH window (and `/gratuity prices`): all mats in about a minute, click again to stop.
- Prices also come from your own AH searches and from merchants that sell a mat.
- With Auctionator installed, its prices are used when they are newer (setting).
- Mat tooltips show where a price came from and when it was checked; mats with no listings show "none on the AH".

## 1.2.1
- Fixed an error when clicking into the Custom % box.

## 1.2.0
- Clicking an enchant link in chat opens Gratuity on that enchant (setting).
- The Custom % box is easier to spot and lights up while in use.

## 1.1.1
- Rounding steps grow with the tip, so the % buttons always change cheap tips too.

## 1.1.0
- One window: enchant list on the left, the selected enchant on the right, tip first and large.
- Default tip 10 %, the last % you pick is remembered; sensible rounding.

## 1.0.2
- Own icon on the minimap button and in the add-on compartment.
- Sort the list by slot, name, cheapest or dearest.
- Advert channel reset to TradeLocal; easier-to-read secondary text.

## 1.0.0
- *Still to buy* line, your own price per mat (right-click), old prices marked orange/red.

## 0.x (testing)
- Enchant list, detail view, settings, minimap button, advert buttons, Search AH (via Auctionator), `{link}` in the message.
