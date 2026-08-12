import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

class PageScaffold extends StatelessWidget {
  const PageScaffold({
    required this.title,
    required this.body,
    this.description,
    this.tabs,
    this.primaryAction,
    this.contentPadding,
    super.key,
  });

  final String title;
  final String? description;
  final Widget? tabs;
  final Widget? primaryAction;
  final Widget body;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ColoredBox(
      color: tokens.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.shellSurface,
              border: Border(bottom: BorderSide(color: tokens.borderFaint)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppLayout.pageHeaderMinHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppLayout.pageHorizontalPadding,
                  22,
                  AppLayout.pageHorizontalPadding,
                  0,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 620;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (compact)
                          _CompactTitleRow(
                            title: title,
                            primaryAction: primaryAction,
                          )
                        else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _TitleBlock(title: title)),
                              if (primaryAction != null) ...[
                                const SizedBox(width: 20),
                                primaryAction!,
                              ],
                            ],
                          ),
                        if (description case final text?
                            when text.trim().isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: tokens.textSecondary),
                          ),
                        ],
                        if (tabs != null) ...[
                          const SizedBox(height: 10),
                          tabs!,
                        ] else
                          const SizedBox(height: 14),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding:
                  contentPadding ??
                  const EdgeInsets.fromLTRB(
                    AppLayout.pageHorizontalPadding,
                    AppLayout.pageContentTopPadding,
                    AppLayout.pageHorizontalPadding,
                    AppLayout.pageHorizontalPadding,
                  ),
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.6,
      ),
    );
  }
}

class _CompactTitleRow extends StatelessWidget {
  const _CompactTitleRow({required this.title, this.primaryAction});

  final String title;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 10,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _TitleBlock(title: title),
        if (primaryAction != null) primaryAction!,
      ],
    );
  }
}
