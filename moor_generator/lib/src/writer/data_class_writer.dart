import 'package:moor_generator/src/model/specified_table.dart';
import 'package:moor_generator/src/options.dart';
import 'package:recase/recase.dart';

const _hashCombine = '\$mrjc';
const _hashFinish = '\$mrjf';

class DataClassWriter {
  final SpecifiedTable table;
  final MoorOptions options;

  DataClassWriter(this.table, this.options);

  void writeInto(StringBuffer buffer) {
    buffer.write(
        'class ${table.dartTypeName} extends DataClass implements Insertable<${table.dartTypeName}> {\n');

    // write individual fields
    for (var column in table.columns) {
      buffer.write('final ${column.dartTypeName} ${column.dartGetterName}; \n');
    }

    // write constructor with named optional fields
    buffer
      ..write(table.dartTypeName)
      ..write('({')
      ..write(table.columns.map((column) {
        if (column.nullable) {
          return 'this.${column.dartGetterName}';
        } else {
          return '@required this.${column.dartGetterName}';
        }
      }).join(', '))
      ..write('});');

    // Also write parsing factory
    _writeMappingConstructor(buffer);

    // And a serializer and deserializer method
    _writeFromJson(buffer);
    _writeToJson(buffer);
    _writeCompanionOverride(buffer);

    // And a convenience method to copy data from this class.
    _writeCopyWith(buffer);

    _writeToString(buffer);
    _writeHashCode(buffer);

    // override ==
    //    return identical(this, other) || (other is DataClass && other.id == id && ...)
    buffer
      ..write('@override\nbool operator ==(other) => ')
      ..write('identical(this, other) || (other is ${table.dartTypeName}');

    if (table.columns.isNotEmpty) {
      buffer
        ..write('&&')
        ..write(table.columns.map((c) {
          final getter = c.dartGetterName;

          return 'other.$getter == $getter';
        }).join(' && '));
    }

    // finish overrides method and class declaration
    buffer.write(');\n}');
  }

  void _writeMappingConstructor(StringBuffer buffer) {
    final dataClassName = table.dartTypeName;

    buffer
      ..write('factory $dataClassName.fromData')
      ..write('(Map<String, dynamic> data, GeneratedDatabase db, ')
      ..write('{String prefix}) {\n')
      ..write("final effectivePrefix = prefix ?? '';");

    final dartTypeToResolver = <String, String>{};

    final types = table.columns.map((c) => c.dartTypeName).toSet();
    for (var usedType in types) {
      // final intType = db.typeSystem.forDartType<int>();
      final resolver = '${ReCase(usedType).camelCase}Type';
      dartTypeToResolver[usedType] = resolver;

      buffer
          .write('final $resolver = db.typeSystem.forDartType<$usedType>();\n');
    }

    // finally, the mighty constructor invocation:
    buffer.write('return $dataClassName(');

    for (var column in table.columns) {
      // id: intType.mapFromDatabaseResponse(data["id])
      final getter = column.dartGetterName;
      final resolver = dartTypeToResolver[column.dartTypeName];
      final columnName = "'\${effectivePrefix}${column.name.name}'";
      final typeParser = '$resolver.mapFromDatabaseResponse(data[$columnName])';

      buffer.write('$getter: $typeParser,');
    }

    buffer.write(');}\n');
  }

  void _writeFromJson(StringBuffer buffer) {
    final dataClassName = table.dartTypeName;

    buffer
      ..write('factory $dataClassName.fromJson('
          'Map<String, dynamic> json,'
          '{ValueSerializer serializer = const ValueSerializer.defaults()}'
          ') {\n')
      ..write('return $dataClassName(');

    for (var column in table.columns) {
      final getter = column.dartGetterName;
      final jsonKey = column.jsonKey;
      final type = column.dartTypeName;

      buffer.write("$getter: serializer.fromJson<$type>(json['$jsonKey']),");
    }

    buffer.write(');}\n');

    if (options.generateFromJsonStringConstructor) {
      // also generate a constructor that only takes a json string
      buffer.write('factory $dataClassName.fromJsonString(String encodedJson, '
          '{ValueSerializer serializer = const ValueSerializer.defaults()}) => '
          '$dataClassName.fromJson('
          'DataClass.parseJson(encodedJson) as Map<String, dynamic>, '
          'serializer: serializer);');
    }
  }

  void _writeToJson(StringBuffer buffer) {
    buffer.write('@override Map<String, dynamic> toJson('
        '{ValueSerializer serializer = const ValueSerializer.defaults()}) {'
        '\n return {');

    for (var column in table.columns) {
      final name = column.jsonKey;
      final getter = column.dartGetterName;
      final needsThis = getter == 'serializer';
      final value = needsThis ? 'this.$getter' : getter;

      buffer
          .write("'$name': serializer.toJson<${column.dartTypeName}>($value),");
    }

    buffer.write('};}');
  }

  void _writeCopyWith(StringBuffer buffer) {
    final dataClassName = table.dartTypeName;

    buffer.write('$dataClassName copyWith({');
    for (var i = 0; i < table.columns.length; i++) {
      final column = table.columns[i];
      final last = i == table.columns.length - 1;

      buffer.write('${column.dartTypeName} ${column.dartGetterName}');
      if (!last) {
        buffer.write(',');
      }
    }

    buffer.write('}) => $dataClassName(');

    for (var column in table.columns) {
      // we also have a method parameter called like the getter, so we can use
      // field: field ?? this.field
      final getter = column.dartGetterName;
      buffer.write('$getter: $getter ?? this.$getter,');
    }

    buffer.write(');');
  }

  void _writeToString(StringBuffer buffer) {
    /*
      @override
      String toString() {
        return (StringBuffer('User(')
            ..write('id: $id,')
            ..write('name: $name,')
            ..write('isAwesome: $isAwesome')
            ..write(')')).toString();
      }
     */

    buffer
      ..write('@override\nString toString() {')
      ..write("return (StringBuffer('${table.dartTypeName}(')");

    for (var i = 0; i < table.columns.length; i++) {
      final column = table.columns[i];
      final getterName = column.dartGetterName;

      buffer.write("..write('$getterName: \$$getterName");
      if (i != table.columns.length - 1) buffer.write(', ');

      buffer.write("')");
    }

    buffer..write("..write(')')).toString();")..write('\}\n');
  }

  void _writeHashCode(StringBuffer buffer) {
    buffer.write('@override\n int get hashCode => ');

    if (table.columns.isEmpty) {
      buffer.write('identityHashCode(this); \n');
    } else {
      final fields = table.columns.map((c) => c.dartGetterName).toList();
      buffer
        ..write('$_hashFinish(')
        ..write(_calculateHashCode(fields))
        ..write(')')
        ..write('; \n');
    }
  }

  void _writeCompanionOverride(StringBuffer buffer) {
    // T createCompanion<T extends UpdateCompanion>(bool nullToAbsent)

    final companionClass = table.updateCompanionName;
    buffer.write('@override\nT createCompanion<T extends UpdateCompanion'
        '<${table.dartTypeName}>>('
        'bool nullToAbsent) {\n return $companionClass(');

    for (var column in table.columns) {
      final getter = column.dartGetterName;
      buffer.write('$getter: $getter == null && nullToAbsent ? '
          'const Value.absent() : Value($getter),');
    }
    buffer.write(') as T;}\n');
  }

  /// Recursively creates the implementation for hashCode of the data class,
  /// assuming it has at least one field. When it has one field, we just return
  /// the hash code of that field. Otherwise, we multiply it with 31 and add
  /// the hash code of the next field, and so on.
  String _calculateHashCode(List<String> fields) {
    if (fields.length == 1) {
      return '$_hashCombine(0, ${fields.last}.hashCode)';
    } else {
      final last = fields.removeLast();
      final innerHash = _calculateHashCode(fields);

      return '$_hashCombine($innerHash, $last.hashCode)';
    }
  }
}
