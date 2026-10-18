import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/routes/prices_routes.dart';
import '../../../../domain/models/product.dart';
import '../../../../domain/use_cases/filter_products.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../places/views/stored_image.dart';
import '../view_models/catalog_providers.dart';
import 'category_chips.dart';
import 'manage_categories_sheet.dart';

/// All products, filtered by category chips and a search box. Tap one to open its
/// page. (Reached from the Prices card on Home.)
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  String _query = '';
  String? _categoryId;

  void _back() => context.canPop() ? context.pop() : context.go(Routes.home);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final products = ref.watch(productsProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final categoryName = {for (final cat in categories) cat.id: cat.name};

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.lg,
                Space.gutter,
                Space.md,
              ),
              child: Row(
                children: [
                  Semantics(
                    container: true,
                    button: true,
                    label: 'Back',
                    excludeSemantics: true,
                    child: Squish(
                      onTap: _back,
                      child: Container(
                        width: Chrome.minTouch,
                        height: Chrome.minTouch,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: c.line),
                        ),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          size: 20,
                          color: c.text,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(child: Text('Products', style: t.headlineSmall)),
                  IconButton(
                    tooltip: 'Edit categories',
                    icon: Icon(Icons.tune_rounded, color: c.muted),
                    onPressed: () => showManageCategories(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: TextField(
                textDirection: null,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search products',
                  prefixIcon: Icon(Icons.search_rounded, color: c.muted),
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: CategoryChips(
                selectedId: _categoryId,
                onSelected: (id) => setState(() => _categoryId = id),
                showAll: true,
              ),
            ),
            Expanded(
              child: products.when(
                loading: () =>
                    const SkeletonList(padding: EdgeInsets.all(Space.gutter)),
                error: (_, _) =>
                    const EmptyState(message: 'Could not load your products.'),
                data: (all) {
                  final shown = filterProducts(
                    all,
                    query: _query,
                    categoryId: _categoryId,
                  );
                  if (shown.isEmpty) {
                    return EmptyState(
                      message: all.isEmpty
                          ? 'No products yet. Log your first price.'
                          : 'No product matches.',
                      actionLabel: all.isEmpty ? 'Log price' : null,
                      onAction: all.isEmpty
                          ? () => context.push(logPriceLocation())
                          : null,
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      Space.sm,
                      Space.gutter,
                      Chrome.contentBottomPadding,
                    ),
                    itemCount: shown.length,
                    itemBuilder: (context, i) => _ProductRow(
                      product: shown[i],
                      category: categoryName[shown[i].categoryId],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.category});

  final Product product;
  final String? category;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final named = product.variants.where((v) => v.name != null).length;
    final subtitle = [
      ?product.brand,
      ?category,
      if (named > 1) '$named variants',
    ].join(' · ');
    final photo = product.photoPath;
    return Semantics(
      container: true,
      button: true,
      label: '${product.name}${subtitle.isEmpty ? '' : ', $subtitle'}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: Radii.inputR,
        onTap: () => context.push(Routes.productDetail(product.id)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 40,
                  height: 40,
                  color: c.raised,
                  alignment: Alignment.center,
                  child: photo != null
                      ? SizedBox(
                          width: 40,
                          height: 40,
                          child: StoredImage(path: photo, cacheWidth: 120),
                        )
                      : _Initial(product.name),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: t.titleMedium?.copyWith(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: t.bodySmall?.copyWith(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Text(
    name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase(),
    style: Theme.of(context).textTheme.titleMedium,
  );
}
