import '../core/ids.dart';
import 'models.dart';

/// Default categories (no invented transactions). Personal and Daily are neutral discretionary names.
List<Category> defaultCategories() {
  const spec = [
    ('Fast Food', 0xFFFF8A65, 1, 'fast_food', false),
    ('Restaurants', 0xFFFFB74D, 2, null, false),
    ('Groceries', 0xFF81C784, 3, 'groceries', true),
    ('Snacks', 0xFFFFD54F, 4, null, false),
    ('Drinks', 0xFF4FC3F7, 5, null, false),
    ('Gas', 0xFF90A4AE, 6, 'gas', true),
    ('Insurance', 0xFF7986CB, 7, null, true),
    ('Rent', 0xFF9575CD, 8, null, true),
    ('Subscriptions', 0xFFBA68C8, 9, null, false),
    ('Shopping', 0xFFF06292, 10, null, false),
    ('Entertainment', 0xFF4DD0E1, 11, null, false),
    ('Personal', 0xFFA1887F, 12, null, false),
    ('Daily', 0xFFAED581, 13, null, false),
    ('Miscellaneous', 0xFFB0BEC5, 0, null, false),
  ];
  return [
    for (var i = 0; i < spec.length; i++)
      Category(id: newId(), name: spec[i].$1, color: spec[i].$2, icon: spec[i].$3, tag: spec[i].$4,
          essential: spec[i].$5, sort: i)
  ];
}
