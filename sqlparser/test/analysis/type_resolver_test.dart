import 'package:sqlparser/sqlparser.dart';
import 'package:test/test.dart';

import 'data.dart';

Map<String, ResolveResult> _types = {
  'SELECT * FROM demo WHERE id = ?':
      const ResolveResult(ResolvedType(type: BasicType.int)),
  'SELECT * FROM demo WHERE content = ?':
      const ResolveResult(ResolvedType(type: BasicType.text)),
  'SELECT * FROM demo LIMIT ?':
      const ResolveResult(ResolvedType(type: BasicType.int)),
  'SELECT 1 FROM demo GROUP BY id HAVING COUNT(*) = ?':
      const ResolveResult(ResolvedType(type: BasicType.int)),
  'SELECT 1 FROM demo WHERE id BETWEEN 3 AND ?':
      const ResolveResult(ResolvedType(type: BasicType.int)),
  'UPDATE demo SET content = ? WHERE id = 3':
      const ResolveResult(ResolvedType(type: BasicType.text)),
  'SELECT * FROM demo WHERE content LIKE ?':
      const ResolveResult(ResolvedType(type: BasicType.text)),
  "SELECT * FROM demo WHERE content LIKE '%e' ESCAPE ?":
      const ResolveResult(ResolvedType(type: BasicType.text)),
  'SELECT * FROM demo WHERE content IN ?':
      const ResolveResult(ResolvedType(type: BasicType.text, isArray: true)),
  'SELECT * FROM demo WHERE content IN (?)':
      const ResolveResult(ResolvedType(type: BasicType.text, isArray: false)),
  'SELECT * FROM demo JOIN table ON demo.id = table.id WHERE date = ?':
      const ResolveResult(
          ResolvedType(type: BasicType.int, hint: IsDateTime())),
};

void main() {
  _types.forEach((sql, resolvedType) {
    test('types: resolves in $sql', () {
      final engine = SqlEngine()
        ..registerTable(demoTable)
        ..registerTable(anotherTable);
      final content = engine.analyze(sql);

      final variable = content.root.allDescendants
          .firstWhere((node) => node is Variable) as Typeable;

      expect(content.typeOf(variable), equals(resolvedType));
    });
  });
}
