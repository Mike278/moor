---
layout: feature
title: Custom queries
parent: Writing queries
permalink: /queries/custom
---

# Custom statements
Altough moor includes a fluent api that can be used to model most statements, advanced
features like `GROUP BY` statements or window functions are not yet supported. You can
use these features with custom statements. You don't have to miss out on other benefits
moor brings, though: Parsing the rows and query-streams also work on custom statements.

## Statements with a generated api
Starting from version `1.5`, you can instruct moor to automatically generate a typesafe
API for your select statements. At the moment, this feature is in an experimental state
but it can already handle most statements (`select`, `update` and `delete`). Of course,
you can still write custom sql manually. See the sections below for details.

To use this feature, all you need to is define your queries in your `UseMoor` annotation:
```dart
@UseMoor(
  tables: [Todos, Categories],
  queries: {
    'categoriesWithCount':
        'SELECT *, (SELECT COUNT(*) FROM todos WHERE category = c.id) AS "amount" FROM categories c;'
  },
)
class MyDatabase extends _$MyDatabase {
  // rest of class stays the same
}
```
After running the build step again, moor will have written the `CategoriesWithCountResult` class for you -
it will hold the result of your query. Also, the `_$MyDatabase` class from which you inherit will have the
methods `categoriesWithCount` (which runs the query once) and `watchCategoriesWithCount` (which returns
an auto-updating stream).

Queries can have parameters in them by using the `?` or `:name` syntax. When your queries contain parameters,
moor will figure out an appropriate type for them and include them in the generated methods. For instance,
`'categoryById': 'SELECT * FROM categories WHERE id = :id'` will generate the method `categoryById(int id)`.

You can also use `UPDATE` or `DELETE` statements here. Of course, this feature is also available for [daos]({{"/daos" | absolute_url}}),
and it perfectly integrates with auto-updating streams by analyzing what tables you're reading from or
writing to.

## Custom select statements
You can issue custom queries by calling `customSelect` for a one-time query or
`customSelectStream` for a query stream that automatically emits a new set of items when
the underlying data changes. Using the todo example introduced in the 
[getting started guide]({{site.common_links.getting_started | absolute_url}}), we can
write this query which will load the amount of todo entries in each category:
```dart
class CategoryWithCount {
  final Category category;
  final int count; // amount of entries in this category

  CategoryWithCount(this.category, this.count);
}

// then, in the database class:
Stream<List<CategoryWithCount>> categoriesWithCount() {
    // select all categories and load how many associated entries there are for
    // each category
    return customSelectStream(
      'SELECT *, (SELECT COUNT(*) FROM todos WHERE category = c.id) AS "amount" FROM categories c;',
      readsFrom: {todos, categories}, // used for the stream: the stream will update when either table changes
      ).map((rows) {
        // we get list of rows here. We just have to turn the raw data from the row into a
        // CategoryWithCount. As we defined the Category table earlier, moor knows how to parse
        // a category. The only thing left to do manually is extracting the amount
        return rows
          .map((row) => CategoryWithCount(Category.fromData(row.data, this), row.readInt('amount')))
          .toList();
    });
  }
```
For custom selects, you should use the `readsFrom` parameter to specify from which tables the query is
reading. When using a `Stream`, moor will be able to know after which updates the stream should emit
items. 

## Custom update statements
For update and delete statements, you can use `customUpdate`. Just like `customSelect`, that method
also takes a sql statement and optional variables. You can also tell moor which tables will be
affected by your query using the optional `updates` parameter. That will help with other select
streams, which will then update automatically.
