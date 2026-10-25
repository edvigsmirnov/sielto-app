import 'package:easy_localization/easy_localization.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/layout.dart';
import 'package:sielto/core/ui/popover.dart';
import 'package:sielto/features/categories/category_icons.dart';

/// Any emoji, by group or by name; a typed or pasted one is offered too.
Future<String?> pickEmoji(BuildContext context) => showAdaptiveSheet<String>(
  context,
  dragHandle: true,
  width: 480,
  builder: (BuildContext _) => const _EmojiSheet(),
);

/// Every character is an emoji the picker knows, skin tones aside.
bool isEmojiOnly(String text) =>
    text.characters.every((String c) => _known.contains(_bare(c)));

final RegExp _modifiers = RegExp('[\uFE0F\u{1F3FB}-\u{1F3FF}]', unicode: true);

String _bare(String emoji) => emoji.replaceAll(_modifiers, '');

final Set<String> _known = <String>{
  for (final CategoryEmoji group in defaultEmojiSet)
    for (final Emoji e in group.emoji) _bare(e.emoji),
};

class _EmojiSheet extends StatefulWidget {
  const _EmojiSheet();

  @override
  State<_EmojiSheet> createState() => _EmojiSheetState();
}

class _EmojiSheetState extends State<_EmojiSheet> {
  String _query = '';
  List<Emoji>? _found;
  Category? _start;
  final GlobalKey<EmojiPickerState> _picker = GlobalKey<EmojiPickerState>();

  static const TextStyle _glyph = TextStyle(fontFamilyFallback: emojiFonts);

  @override
  void initState() {
    super.initState();
    EmojiPickerUtils().getRecentEmojis().then((List<RecentEmoji> recent) {
      if (mounted) {
        setState(
          () => _start = recent.isEmpty ? Category.SMILEYS : Category.RECENT,
        );
      }
    });
  }

  Future<void> _search(String value) async {
    final String query = value.trim();
    setState(() => _query = query);
    if (query.isEmpty) return setState(() => _found = null);
    final List<Emoji> hits = await EmojiPickerUtils().searchEmoji(
      query,
      getDefaultEmojiLocale(context.locale),
    );
    if (!mounted || query != _query) return;
    final String? typed = sanitiseCategoryIcon(query);
    setState(
      () => _found = <Emoji>[
        if (typed != null && isEmojiOnly(typed)) Emoji(typed, ''),
        for (final Emoji e in hits)
          if (e.emoji != typed) e,
      ],
    );
  }

  void _choose(Emoji emoji) {
    EmojiPickerUtils().addEmojiToRecentlyUsed(key: _picker, emoji: emoji);
    Navigator.of(context).pop(emoji.emoji);
  }

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final List<Emoji>? found = _found;
    // The popover's card, the sheet's surface.
    final Color ground = isWide(context) ? sage.card : sage.surface;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: 440,
          child: Column(
            children: <Widget>[
              Text(
                tr('category.fieldIcon'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Padding(
                padding: const EdgeInsets.all(SageSpace.gutter),
                child: TextField(
                  autofocus: desktopInput,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: tr('category.searchEmoji'),
                    isDense: true,
                  ),
                  onChanged: _search,
                  onSubmitted: (String _) {
                    if (found?.isNotEmpty ?? false) {
                      _choose(found!.first);
                    }
                  },
                ),
              ),
              Expanded(
                child: found != null
                    ? _Found(emoji: found, onTap: _choose)
                    : _start == null
                    ? const SizedBox.shrink()
                    : EmojiPicker(
                        key: _picker,
                        onEmojiSelected: (Category? _, Emoji emoji) =>
                            Navigator.of(context).pop(emoji.emoji),
                        config: Config(
                          height: null,
                          locale: context.locale,
                          emojiTextStyle: _glyph,
                          emojiViewConfig: EmojiViewConfig(
                            columns: 8,
                            backgroundColor: ground,
                            noRecents: Text(
                              tr('category.noRecentEmoji'),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          categoryViewConfig: CategoryViewConfig(
                            initCategory: _start!,
                            backgroundColor: ground,
                            indicatorColor: sage.accentStrong,
                            iconColor: sage.inkLabel,
                            iconColorSelected: sage.accentStrong,
                            dividerColor: sage.hairline,
                            customCategoryView:
                                (
                                  Config config,
                                  EmojiViewState state,
                                  TabController tabs,
                                  PageController pages,
                                ) => _GroupTabs(
                                  config: config,
                                  groups: state.categoryEmoji,
                                  tabs: tabs,
                                  pages: pages,
                                ),
                          ),
                          skinToneConfig: SkinToneConfig(
                            dialogBackgroundColor: sage.cardRaised,
                            indicatorColor: sage.inkLabel,
                          ),
                          bottomActionBarConfig: const BottomActionBarConfig(
                            enabled: false,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Found extends StatelessWidget {
  const _Found({required this.emoji, required this.onTap});

  final List<Emoji> emoji;
  final ValueChanged<Emoji> onTap;

  @override
  Widget build(BuildContext context) => emoji.isEmpty
      ? Center(
          child: Text(
            tr('category.noEmoji'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        )
      : GridView.extent(
          maxCrossAxisExtent: 52,
          padding: const EdgeInsets.symmetric(horizontal: SageSpace.gutter),
          children: <Widget>[
            for (final Emoji e in emoji)
              InkWell(
                onTap: () => onTap(e),
                borderRadius: BorderRadius.circular(SageRadius.button),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    e.emoji,
                    style: const TextStyle(
                      fontSize: 28,
                      fontFamilyFallback: emojiFonts,
                    ),
                  ),
                ),
              ),
          ],
        );
}

/// The package's bar, with 48 dp tabs that say which group they are.
class _GroupTabs extends StatelessWidget {
  const _GroupTabs({
    required this.config,
    required this.groups,
    required this.tabs,
    required this.pages,
  });

  final Config config;
  final List<CategoryEmoji> groups;
  final TabController tabs;
  final PageController pages;

  @override
  Widget build(BuildContext context) {
    final CategoryViewConfig view = config.categoryViewConfig;
    return ColoredBox(
      color: view.backgroundColor,
      child: TabBar(
        controller: tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.center,
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
        labelColor: view.iconColorSelected,
        unselectedLabelColor: view.iconColor,
        indicatorColor: view.indicatorColor,
        dividerColor: view.dividerColor,
        onTap: pages.jumpToPage,
        tabs: <Widget>[
          for (final CategoryEmoji group in groups)
            Tooltip(
              message: tr(
                'category.emojiGroup.${group.category.name.toLowerCase()}',
              ),
              child: Tab(
                icon: Icon(
                  getIconForCategory(view.categoryIcons, group.category),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
