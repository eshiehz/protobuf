//
//  GPBArray2.cpp
//  ProtocolBuffers_iOS
//
//  Created by Eric Shieh on 10/5/17.
//
//

#import "GPBArray_PackagePrivate.h"

#import "GPBMessage_PackagePrivate.h"
#include "GPBArray.h"
#import <Foundation/Foundation.h>
#include <sstream>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"

#define kChunkSize 16
#define CapacityFromCount(x) (((x / kChunkSize) + 1) * kChunkSize)
static BOOL ArrayDefault_IsValidValue(int32_t value) {
  // Anything but the bad value marker is allowed.
  return (value != kGPBUnrecognizedEnumeratorValue);
}


template <typename T>
class GPBArrayHelper {
public:
  T *_values;
  NSUInteger _count;
  NSUInteger _capacity;
  
public:
  static id array(Class cls);
  GPBArrayHelper();
  ~GPBArrayHelper();
  id initWithValues(id self,const T values[],NSUInteger count);
  void internalResizeToCapacity(NSUInteger capacity);
  BOOL isEqual(const GPBArrayHelper<T> &obj);
  NSString * description(id obj);
  void enumerateValuesWithOptions(NSEnumerationOptions opts,
                                  void (^block)(T value, NSUInteger idx, BOOL *stop));
  T valueAtIndex(NSUInteger index);
  void addValues(const T values[],NSUInteger count);
  void insertValue(T value,NSUInteger index);
  void replaceValueAtIndex(NSUInteger index,T value);
  void removeValueAtIndex(NSUInteger index);
  void removeAll();
  void exchangeValueAtIndex(NSUInteger idx1,NSUInteger idx2);
};

template <typename T>
class GPBArrayEnumHelper : public GPBArrayHelper<T> {
public:
  GPBEnumValidationFunc _validationFunc;
  
public:
  
};

template <typename T> id GPBArrayHelper<T>::array(Class cls) {
  return [[cls alloc] init];
}

template<typename T> GPBArrayHelper<T>::GPBArrayHelper():_values(NULL),_count(0),_capacity(0) {
}

template<typename T> GPBArrayHelper<T>::~GPBArrayHelper() {
  if (_values) {
    free(_values);
  }
}

template<typename T> id GPBArrayHelper<T>::initWithValues(id self,const T values[],
                                                          NSUInteger count) {
  if (self) {
    if (count && values) {
      _values = (T *)reallocf(_values, count * sizeof(T));
      if (_values != NULL) {
        _capacity = count;
        memcpy(_values, values, count * sizeof(T));
        _count = count;
      } else {
        [self release];
        [NSException raise:NSMallocException
                    format:@"Failed to allocate %lu bytes",
         (unsigned long)(count * sizeof(T))];
      }
    }
  }
  return self;
}

template<typename T> void GPBArrayHelper<T>::internalResizeToCapacity(NSUInteger newCapacity) {
  _values = (T *)reallocf(_values, newCapacity * sizeof(T));
  if (_values == NULL) {
    _capacity = 0;
    _count = 0;
    [NSException raise:NSMallocException
                format:@"Failed to allocate %lu bytes",
     (unsigned long)(newCapacity * sizeof(T))];
  }
  _capacity = newCapacity;
}

template<typename T> BOOL GPBArrayHelper<T>::isEqual(const GPBArrayHelper<T> &otherArray) {
  
  return (_count == otherArray._count
          && memcmp(_values, otherArray._values, (_count * sizeof(T))) == 0);
}
template<typename T> NSString * GPBArrayHelper<T>::description(id obj) {
  NSMutableString *result = [NSMutableString stringWithFormat:@"<%@ %p> { ", [obj class], obj];
  for (NSUInteger i = 0, count = _count; i < count; ++i) {
    /*std::ostringstream output;
    output << _values[i];
    if (i == 0) {
      [result appendFormat:@"%s", output.str().c_str()];
    } else {
      [result appendFormat:@", %s", output.str().c_str()];
    }
     */
  }
  [result appendFormat:@" }"];
  return result;
}

template<typename T> void GPBArrayHelper<T>::enumerateValuesWithOptions(NSEnumerationOptions opts,
  void (^block)(T value, NSUInteger idx, BOOL *stop)){
  // NSEnumerationConcurrent isn't currently supported (and Apple's docs say that is ok).
  BOOL stop = NO;
  if ((opts & NSEnumerationReverse) == 0) {
    for (NSUInteger i = 0, count = _count; i < count; ++i) {
      block(_values[i], i, &stop);
      if (stop) break;
    }
  } else if (_count > 0) {
    for (NSUInteger i = _count; i > 0; --i) {
      block(_values[i - 1], (i - 1), &stop);
      if (stop) break;
    }
  }
}
template<typename T> T GPBArrayHelper<T>::valueAtIndex(NSUInteger index){
  if (index >= _count) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)index, (unsigned long)_count];
  }
  return _values[index];
}

template<typename T> void GPBArrayHelper<T>::addValues(const T values[],NSUInteger count) {
  if (values == NULL || count == 0) return;
  NSUInteger initialCount = _count;
  NSUInteger newCount = initialCount + count;
  if (newCount > _capacity) {
    internalResizeToCapacity(CapacityFromCount(newCount));
  }
  _count = newCount;
  memcpy(&_values[initialCount], values, count * sizeof(T));
}
template<typename T> void GPBArrayHelper<T>::insertValue(T value,NSUInteger index) {
  if (index >= _count + 1) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)index, (unsigned long)_count + 1];
  }
  NSUInteger initialCount = _count;
  NSUInteger newCount = initialCount + 1;
  if (newCount > _capacity) {
    internalResizeToCapacity(CapacityFromCount(newCount));
  }
  _count = newCount;
  if (index != initialCount) {
    memmove(&_values[index + 1], &_values[index], (initialCount - index) * sizeof(T));
  }
  _values[index] = value;
}

template<typename T> void GPBArrayHelper<T>::replaceValueAtIndex(NSUInteger index,T value) {
  if (index >= _count) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)index, (unsigned long)_count];
  }
  _values[index] = value;
}

template<typename T> void GPBArrayHelper<T>::removeValueAtIndex(NSUInteger index) {
  if (index >= _count) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)index, (unsigned long)_count];
  }
  NSUInteger newCount = _count - 1;
  if (index != newCount) {
    memmove(&_values[index], &_values[index + 1], (newCount - index) * sizeof(T));
  }
  _count = newCount;
  if ((newCount + (2 * kChunkSize)) < _capacity) {
    internalResizeToCapacity(CapacityFromCount(newCount));
  }
}

template<typename T> void GPBArrayHelper<T>::removeAll() {
  _count = 0;
  if ((0 + (2 * kChunkSize)) < _capacity) {
    internalResizeToCapacity(CapacityFromCount(0));
  }
}
template<typename T> void GPBArrayHelper<T>::exchangeValueAtIndex(NSUInteger idx1,NSUInteger idx2){
  if (idx1 >= _count) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)idx1, (unsigned long)_count];
  }
  if (idx2 >= _count) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)idx2, (unsigned long)_count];
  }
  T temp = _values[idx1];
  _values[idx1] = _values[idx2];
  _values[idx2] = temp;
}
//%PDDM-DEFINE DEFINE_ARRAY(LABEL,TYPE,STORAGE)
//%static_assert(sizeof(TYPE) == sizeof(STORAGE),"sizes do not match");
//%@implementation GPB##LABEL##Array {
//%  @package
//%  GPBArrayHelper<STORAGE> _helper;
//%}
//%- (NSUInteger)count {
//%  return _helper._count;
//%}
//%+ (instancetype)array {
//%  return [GPBArrayHelper<STORAGE>::array(self) autorelease];
//%}
//%+ (instancetype)arrayWithValue:(TYPE)value {
//%  return [[(GPB##LABEL##Array*)[self alloc] initWithValues:(TYPE *)&value count:1] autorelease];
//%}
//%+ (instancetype)arrayWithValueArray:(GPB##LABEL##Array *)array {
//%  return [[(GPB##LABEL##Array*)[self alloc] initWithValueArray:array] autorelease];
//%}
//%+ (instancetype)arrayWithCapacity:(NSUInteger)count {
//%  return [[[self alloc] initWithCapacity:count] autorelease];
//%}
//%- (instancetype)init {
//%  self = [super init];
//%  return self;
//%}
//%- (instancetype)initWithValueArray:(GPB##LABEL##Array *)array {
//%  return [self initWithValues:(TYPE *)array->_helper._values count:array->_helper._count];
//%}
//%- (instancetype)initWithValues:(const TYPE[])values count:(NSUInteger)count {
//%  self = [self init];
//%  if (self) {
//%    _helper.initWithValues(self,(STORAGE *)values,count);
//%  }
//%  return self;
//%}
//%- (instancetype)initWithCapacity:(NSUInteger)count {
//%  self = [self initWithValues:NULL count:0];
//%  if (self && count) {
//%  _helper.internalResizeToCapacity(count);
//%  }
//%  return self;
//%}
//%- (instancetype)copyWithZone:(NSZone *)zone {
//%  return [[GPB##LABEL##Array allocWithZone:zone] initWithValues:(TYPE *)self->_helper._values count:self->_helper._count];
//%}
//%- (void)dealloc {
//%  NSAssert2(!_autocreator,
//%         @"%@: Autocreator must be cleared before release, autocreator: %@",
//%         [self class], _autocreator);
//%[super dealloc];
//%}
//%- (BOOL)isEqual:(id)other {
//%  if (self == other) {
//%    return YES;
//%  }
//%  if (![other isKindOfClass:[GPB##LABEL##Array class]]) {
//%    return NO;
//%  }
//%  return _helper.isEqual(((GPB##LABEL##Array *)other)->_helper);
//%}
//%- (NSUInteger)hash {
//%  // Follow NSArray's lead, and use the count as the hash.
//%  return _helper._count;
//%}
//%- (NSString *)description {
//%  return _helper.description(self);
//%}
//%- (void)enumerateValuesWithBlock:(void (^)(TYPE value, NSUInteger idx, BOOL *stop))block {
//%  [self enumerateValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
//%}
//%- (void)enumerateValuesWithOptions:(NSEnumerationOptions)opts
//%  usingBlock:(void (^)(TYPE value, NSUInteger idx, BOOL *stop))block {
//%  void (^block2)(STORAGE value, NSUInteger idx, BOOL *stop) = ^(STORAGE value, NSUInteger idx, BOOL *stop) {
//%    block((TYPE)value,idx,stop);
//%  };
//%  _helper.enumerateValuesWithOptions(opts,block2);
//%}
//%- (TYPE)valueAtIndex:(NSUInteger)index {
//%  return (TYPE)_helper.valueAtIndex(index);
//%}
//%- (void)addValue:(TYPE)value {
//%[self addValues:&value count:1];
//%}
//%- (void)addValues:(const TYPE [])values count:(NSUInteger)count {
//%_helper.addValues((STORAGE *)values,count);
//%  if (_autocreator) {
//%    GPBAutocreatedArrayModified(_autocreator, self);
//%  }
//%}
//%- (void)insertValue:(TYPE)value atIndex:(NSUInteger)index {
//%  _helper.insertValue((STORAGE)value,index);
//%  if (_autocreator) {
//%    GPBAutocreatedArrayModified(_autocreator, self);
//%  }
//%}
//%
//%- (void)replaceValueAtIndex:(NSUInteger)index withValue:(TYPE)value {
//%  _helper.replaceValueAtIndex(index,(STORAGE)value);
//%}
//%- (void)addValuesFromArray:(GPB##LABEL##Array *)array {
//%  [self addValues:(TYPE *)array->_helper._values count:array->_helper._count];
//%}
//%- (void)removeValueAtIndex:(NSUInteger)index {
//%  _helper.removeValueAtIndex(index);
//%}
//%- (void)removeAll {
//%  _helper.removeAll();
//%}
//%- (void)exchangeValueAtIndex:(NSUInteger)idx1
//%  withValueAtIndex:(NSUInteger)idx2 {
//%    _helper.exchangeValueAtIndex(idx1,idx2);
//%}
//%@end
//%


//%PDDM-EXPAND DEFINE_ARRAY(Int32,int32_t,int32_t)
// This block of code is generated, do not edit it directly.

static_assert(sizeof(int32_t) == sizeof(int32_t),"sizes do not match");
@implementation GPBInt32Array {
  @package
  GPBArrayHelper<int32_t> _helper;
}
- (NSUInteger)count {
  return _helper._count;
}
+ (instancetype)array {
  return [GPBArrayHelper<int32_t>::array(self) autorelease];
}
+ (instancetype)arrayWithValue:(int32_t)value {
  return [[(GPBInt32Array*)[self alloc] initWithValues:(int32_t *)&value count:1] autorelease];
}
+ (instancetype)arrayWithValueArray:(GPBInt32Array *)array {
  return [[(GPBInt32Array*)[self alloc] initWithValueArray:array] autorelease];
}
+ (instancetype)arrayWithCapacity:(NSUInteger)count {
  return [[[self alloc] initWithCapacity:count] autorelease];
}
- (instancetype)init {
  self = [super init];
  return self;
}
- (instancetype)initWithValueArray:(GPBInt32Array *)array {
  return [self initWithValues:(int32_t *)array->_helper._values count:array->_helper._count];
}
- (instancetype)initWithValues:(const int32_t[])values count:(NSUInteger)count {
  self = [self init];
  if (self) {
    _helper.initWithValues(self,(int32_t *)values,count);
  }
  return self;
}
- (instancetype)initWithCapacity:(NSUInteger)count {
  self = [self initWithValues:NULL count:0];
  if (self && count) {
  _helper.internalResizeToCapacity(count);
  }
  return self;
}
- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBInt32Array allocWithZone:zone] initWithValues:(int32_t *)self->_helper._values count:self->_helper._count];
}
- (void)dealloc {
  NSAssert2(!_autocreator,
         @"%@: Autocreator must be cleared before release, autocreator: %@",
         [self class], _autocreator);
[super dealloc];
}
- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBInt32Array class]]) {
    return NO;
  }
  return _helper.isEqual(((GPBInt32Array *)other)->_helper);
}
- (NSUInteger)hash {
  // Follow NSArray's lead, and use the count as the hash.
  return _helper._count;
}
- (NSString *)description {
  return _helper.description(self);
}
- (void)enumerateValuesWithBlock:(void (^)(int32_t value, NSUInteger idx, BOOL *stop))block {
  [self enumerateValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
}
- (void)enumerateValuesWithOptions:(NSEnumerationOptions)opts
  usingBlock:(void (^)(int32_t value, NSUInteger idx, BOOL *stop))block {
  void (^block2)(int32_t value, NSUInteger idx, BOOL *stop) = ^(int32_t value, NSUInteger idx, BOOL *stop) {
    block((int32_t)value,idx,stop);
  };
  _helper.enumerateValuesWithOptions(opts,block2);
}
- (int32_t)valueAtIndex:(NSUInteger)index {
  return (int32_t)_helper.valueAtIndex(index);
}
- (void)addValue:(int32_t)value {
[self addValues:&value count:1];
}
- (void)addValues:(const int32_t [])values count:(NSUInteger)count {
_helper.addValues((int32_t *)values,count);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}
- (void)insertValue:(int32_t)value atIndex:(NSUInteger)index {
  _helper.insertValue((int32_t)value,index);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)replaceValueAtIndex:(NSUInteger)index withValue:(int32_t)value {
  _helper.replaceValueAtIndex(index,(int32_t)value);
}
- (void)addValuesFromArray:(GPBInt32Array *)array {
  [self addValues:(int32_t *)array->_helper._values count:array->_helper._count];
}
- (void)removeValueAtIndex:(NSUInteger)index {
  _helper.removeValueAtIndex(index);
}
- (void)removeAll {
  _helper.removeAll();
}
- (void)exchangeValueAtIndex:(NSUInteger)idx1
  withValueAtIndex:(NSUInteger)idx2 {
    _helper.exchangeValueAtIndex(idx1,idx2);
}
@end

//%PDDM-EXPAND DEFINE_ARRAY(Bool,BOOL,char)
// This block of code is generated, do not edit it directly.

static_assert(sizeof(BOOL) == sizeof(char),"sizes do not match");
@implementation GPBBoolArray {
  @package
  GPBArrayHelper<char> _helper;
}
- (NSUInteger)count {
  return _helper._count;
}
+ (instancetype)array {
  return [GPBArrayHelper<char>::array(self) autorelease];
}
+ (instancetype)arrayWithValue:(BOOL)value {
  return [[(GPBBoolArray*)[self alloc] initWithValues:(BOOL *)&value count:1] autorelease];
}
+ (instancetype)arrayWithValueArray:(GPBBoolArray *)array {
  return [[(GPBBoolArray*)[self alloc] initWithValueArray:array] autorelease];
}
+ (instancetype)arrayWithCapacity:(NSUInteger)count {
  return [[[self alloc] initWithCapacity:count] autorelease];
}
- (instancetype)init {
  self = [super init];
  return self;
}
- (instancetype)initWithValueArray:(GPBBoolArray *)array {
  return [self initWithValues:(BOOL *)array->_helper._values count:array->_helper._count];
}
- (instancetype)initWithValues:(const BOOL[])values count:(NSUInteger)count {
  self = [self init];
  if (self) {
    _helper.initWithValues(self,(char *)values,count);
  }
  return self;
}
- (instancetype)initWithCapacity:(NSUInteger)count {
  self = [self initWithValues:NULL count:0];
  if (self && count) {
  _helper.internalResizeToCapacity(count);
  }
  return self;
}
- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBBoolArray allocWithZone:zone] initWithValues:(BOOL *)self->_helper._values count:self->_helper._count];
}
- (void)dealloc {
  NSAssert2(!_autocreator,
         @"%@: Autocreator must be cleared before release, autocreator: %@",
         [self class], _autocreator);
[super dealloc];
}
- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBBoolArray class]]) {
    return NO;
  }
  return _helper.isEqual(((GPBBoolArray *)other)->_helper);
}
- (NSUInteger)hash {
  // Follow NSArray's lead, and use the count as the hash.
  return _helper._count;
}
- (NSString *)description {
  return _helper.description(self);
}
- (void)enumerateValuesWithBlock:(void (^)(BOOL value, NSUInteger idx, BOOL *stop))block {
  [self enumerateValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
}
- (void)enumerateValuesWithOptions:(NSEnumerationOptions)opts
  usingBlock:(void (^)(BOOL value, NSUInteger idx, BOOL *stop))block {
  void (^block2)(char value, NSUInteger idx, BOOL *stop) = ^(char value, NSUInteger idx, BOOL *stop) {
    block((BOOL)value,idx,stop);
  };
  _helper.enumerateValuesWithOptions(opts,block2);
}
- (BOOL)valueAtIndex:(NSUInteger)index {
  return (BOOL)_helper.valueAtIndex(index);
}
- (void)addValue:(BOOL)value {
[self addValues:&value count:1];
}
- (void)addValues:(const BOOL [])values count:(NSUInteger)count {
_helper.addValues((char *)values,count);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}
- (void)insertValue:(BOOL)value atIndex:(NSUInteger)index {
  _helper.insertValue((char)value,index);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)replaceValueAtIndex:(NSUInteger)index withValue:(BOOL)value {
  _helper.replaceValueAtIndex(index,(char)value);
}
- (void)addValuesFromArray:(GPBBoolArray *)array {
  [self addValues:(BOOL *)array->_helper._values count:array->_helper._count];
}
- (void)removeValueAtIndex:(NSUInteger)index {
  _helper.removeValueAtIndex(index);
}
- (void)removeAll {
  _helper.removeAll();
}
- (void)exchangeValueAtIndex:(NSUInteger)idx1
  withValueAtIndex:(NSUInteger)idx2 {
    _helper.exchangeValueAtIndex(idx1,idx2);
}
@end

//%PDDM-EXPAND DEFINE_ARRAY(Double,double,double)
// This block of code is generated, do not edit it directly.

static_assert(sizeof(double) == sizeof(double),"sizes do not match");
@implementation GPBDoubleArray {
  @package
  GPBArrayHelper<double> _helper;
}
- (NSUInteger)count {
  return _helper._count;
}
+ (instancetype)array {
  return [GPBArrayHelper<double>::array(self) autorelease];
}
+ (instancetype)arrayWithValue:(double)value {
  return [[(GPBDoubleArray*)[self alloc] initWithValues:(double *)&value count:1] autorelease];
}
+ (instancetype)arrayWithValueArray:(GPBDoubleArray *)array {
  return [[(GPBDoubleArray*)[self alloc] initWithValueArray:array] autorelease];
}
+ (instancetype)arrayWithCapacity:(NSUInteger)count {
  return [[[self alloc] initWithCapacity:count] autorelease];
}
- (instancetype)init {
  self = [super init];
  return self;
}
- (instancetype)initWithValueArray:(GPBDoubleArray *)array {
  return [self initWithValues:(double *)array->_helper._values count:array->_helper._count];
}
- (instancetype)initWithValues:(const double[])values count:(NSUInteger)count {
  self = [self init];
  if (self) {
    _helper.initWithValues(self,(double *)values,count);
  }
  return self;
}
- (instancetype)initWithCapacity:(NSUInteger)count {
  self = [self initWithValues:NULL count:0];
  if (self && count) {
  _helper.internalResizeToCapacity(count);
  }
  return self;
}
- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBDoubleArray allocWithZone:zone] initWithValues:(double *)self->_helper._values count:self->_helper._count];
}
- (void)dealloc {
  NSAssert2(!_autocreator,
         @"%@: Autocreator must be cleared before release, autocreator: %@",
         [self class], _autocreator);
[super dealloc];
}
- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBDoubleArray class]]) {
    return NO;
  }
  return _helper.isEqual(((GPBDoubleArray *)other)->_helper);
}
- (NSUInteger)hash {
  // Follow NSArray's lead, and use the count as the hash.
  return _helper._count;
}
- (NSString *)description {
  return _helper.description(self);
}
- (void)enumerateValuesWithBlock:(void (^)(double value, NSUInteger idx, BOOL *stop))block {
  [self enumerateValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
}
- (void)enumerateValuesWithOptions:(NSEnumerationOptions)opts
  usingBlock:(void (^)(double value, NSUInteger idx, BOOL *stop))block {
  void (^block2)(double value, NSUInteger idx, BOOL *stop) = ^(double value, NSUInteger idx, BOOL *stop) {
    block((double)value,idx,stop);
  };
  _helper.enumerateValuesWithOptions(opts,block2);
}
- (double)valueAtIndex:(NSUInteger)index {
  return (double)_helper.valueAtIndex(index);
}
- (void)addValue:(double)value {
[self addValues:&value count:1];
}
- (void)addValues:(const double [])values count:(NSUInteger)count {
_helper.addValues((double *)values,count);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}
- (void)insertValue:(double)value atIndex:(NSUInteger)index {
  _helper.insertValue((double)value,index);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)replaceValueAtIndex:(NSUInteger)index withValue:(double)value {
  _helper.replaceValueAtIndex(index,(double)value);
}
- (void)addValuesFromArray:(GPBDoubleArray *)array {
  [self addValues:(double *)array->_helper._values count:array->_helper._count];
}
- (void)removeValueAtIndex:(NSUInteger)index {
  _helper.removeValueAtIndex(index);
}
- (void)removeAll {
  _helper.removeAll();
}
- (void)exchangeValueAtIndex:(NSUInteger)idx1
  withValueAtIndex:(NSUInteger)idx2 {
    _helper.exchangeValueAtIndex(idx1,idx2);
}
@end

//%PDDM-EXPAND DEFINE_ARRAY(Float,float,float)
// This block of code is generated, do not edit it directly.

static_assert(sizeof(float) == sizeof(float),"sizes do not match");
@implementation GPBFloatArray {
  @package
  GPBArrayHelper<float> _helper;
}
- (NSUInteger)count {
  return _helper._count;
}
+ (instancetype)array {
  return [GPBArrayHelper<float>::array(self) autorelease];
}
+ (instancetype)arrayWithValue:(float)value {
  return [[(GPBFloatArray*)[self alloc] initWithValues:(float *)&value count:1] autorelease];
}
+ (instancetype)arrayWithValueArray:(GPBFloatArray *)array {
  return [[(GPBFloatArray*)[self alloc] initWithValueArray:array] autorelease];
}
+ (instancetype)arrayWithCapacity:(NSUInteger)count {
  return [[[self alloc] initWithCapacity:count] autorelease];
}
- (instancetype)init {
  self = [super init];
  return self;
}
- (instancetype)initWithValueArray:(GPBFloatArray *)array {
  return [self initWithValues:(float *)array->_helper._values count:array->_helper._count];
}
- (instancetype)initWithValues:(const float[])values count:(NSUInteger)count {
  self = [self init];
  if (self) {
    _helper.initWithValues(self,(float *)values,count);
  }
  return self;
}
- (instancetype)initWithCapacity:(NSUInteger)count {
  self = [self initWithValues:NULL count:0];
  if (self && count) {
  _helper.internalResizeToCapacity(count);
  }
  return self;
}
- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBFloatArray allocWithZone:zone] initWithValues:(float *)self->_helper._values count:self->_helper._count];
}
- (void)dealloc {
  NSAssert2(!_autocreator,
         @"%@: Autocreator must be cleared before release, autocreator: %@",
         [self class], _autocreator);
[super dealloc];
}
- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBFloatArray class]]) {
    return NO;
  }
  return _helper.isEqual(((GPBFloatArray *)other)->_helper);
}
- (NSUInteger)hash {
  // Follow NSArray's lead, and use the count as the hash.
  return _helper._count;
}
- (NSString *)description {
  return _helper.description(self);
}
- (void)enumerateValuesWithBlock:(void (^)(float value, NSUInteger idx, BOOL *stop))block {
  [self enumerateValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
}
- (void)enumerateValuesWithOptions:(NSEnumerationOptions)opts
  usingBlock:(void (^)(float value, NSUInteger idx, BOOL *stop))block {
  void (^block2)(float value, NSUInteger idx, BOOL *stop) = ^(float value, NSUInteger idx, BOOL *stop) {
    block((float)value,idx,stop);
  };
  _helper.enumerateValuesWithOptions(opts,block2);
}
- (float)valueAtIndex:(NSUInteger)index {
  return (float)_helper.valueAtIndex(index);
}
- (void)addValue:(float)value {
[self addValues:&value count:1];
}
- (void)addValues:(const float [])values count:(NSUInteger)count {
_helper.addValues((float *)values,count);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}
- (void)insertValue:(float)value atIndex:(NSUInteger)index {
  _helper.insertValue((float)value,index);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)replaceValueAtIndex:(NSUInteger)index withValue:(float)value {
  _helper.replaceValueAtIndex(index,(float)value);
}
- (void)addValuesFromArray:(GPBFloatArray *)array {
  [self addValues:(float *)array->_helper._values count:array->_helper._count];
}
- (void)removeValueAtIndex:(NSUInteger)index {
  _helper.removeValueAtIndex(index);
}
- (void)removeAll {
  _helper.removeAll();
}
- (void)exchangeValueAtIndex:(NSUInteger)idx1
  withValueAtIndex:(NSUInteger)idx2 {
    _helper.exchangeValueAtIndex(idx1,idx2);
}
@end

//%PDDM-EXPAND DEFINE_ARRAY(Int64,int64_t,int64_t)
// This block of code is generated, do not edit it directly.

static_assert(sizeof(int64_t) == sizeof(int64_t),"sizes do not match");
@implementation GPBInt64Array {
  @package
  GPBArrayHelper<int64_t> _helper;
}
- (NSUInteger)count {
  return _helper._count;
}
+ (instancetype)array {
  return [GPBArrayHelper<int64_t>::array(self) autorelease];
}
+ (instancetype)arrayWithValue:(int64_t)value {
  return [[(GPBInt64Array*)[self alloc] initWithValues:(int64_t *)&value count:1] autorelease];
}
+ (instancetype)arrayWithValueArray:(GPBInt64Array *)array {
  return [[(GPBInt64Array*)[self alloc] initWithValueArray:array] autorelease];
}
+ (instancetype)arrayWithCapacity:(NSUInteger)count {
  return [[[self alloc] initWithCapacity:count] autorelease];
}
- (instancetype)init {
  self = [super init];
  return self;
}
- (instancetype)initWithValueArray:(GPBInt64Array *)array {
  return [self initWithValues:(int64_t *)array->_helper._values count:array->_helper._count];
}
- (instancetype)initWithValues:(const int64_t[])values count:(NSUInteger)count {
  self = [self init];
  if (self) {
    _helper.initWithValues(self,(int64_t *)values,count);
  }
  return self;
}
- (instancetype)initWithCapacity:(NSUInteger)count {
  self = [self initWithValues:NULL count:0];
  if (self && count) {
  _helper.internalResizeToCapacity(count);
  }
  return self;
}
- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBInt64Array allocWithZone:zone] initWithValues:(int64_t *)self->_helper._values count:self->_helper._count];
}
- (void)dealloc {
  NSAssert2(!_autocreator,
         @"%@: Autocreator must be cleared before release, autocreator: %@",
         [self class], _autocreator);
[super dealloc];
}
- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBInt64Array class]]) {
    return NO;
  }
  return _helper.isEqual(((GPBInt64Array *)other)->_helper);
}
- (NSUInteger)hash {
  // Follow NSArray's lead, and use the count as the hash.
  return _helper._count;
}
- (NSString *)description {
  return _helper.description(self);
}
- (void)enumerateValuesWithBlock:(void (^)(int64_t value, NSUInteger idx, BOOL *stop))block {
  [self enumerateValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
}
- (void)enumerateValuesWithOptions:(NSEnumerationOptions)opts
  usingBlock:(void (^)(int64_t value, NSUInteger idx, BOOL *stop))block {
  void (^block2)(int64_t value, NSUInteger idx, BOOL *stop) = ^(int64_t value, NSUInteger idx, BOOL *stop) {
    block((int64_t)value,idx,stop);
  };
  _helper.enumerateValuesWithOptions(opts,block2);
}
- (int64_t)valueAtIndex:(NSUInteger)index {
  return (int64_t)_helper.valueAtIndex(index);
}
- (void)addValue:(int64_t)value {
[self addValues:&value count:1];
}
- (void)addValues:(const int64_t [])values count:(NSUInteger)count {
_helper.addValues((int64_t *)values,count);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}
- (void)insertValue:(int64_t)value atIndex:(NSUInteger)index {
  _helper.insertValue((int64_t)value,index);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)replaceValueAtIndex:(NSUInteger)index withValue:(int64_t)value {
  _helper.replaceValueAtIndex(index,(int64_t)value);
}
- (void)addValuesFromArray:(GPBInt64Array *)array {
  [self addValues:(int64_t *)array->_helper._values count:array->_helper._count];
}
- (void)removeValueAtIndex:(NSUInteger)index {
  _helper.removeValueAtIndex(index);
}
- (void)removeAll {
  _helper.removeAll();
}
- (void)exchangeValueAtIndex:(NSUInteger)idx1
  withValueAtIndex:(NSUInteger)idx2 {
    _helper.exchangeValueAtIndex(idx1,idx2);
}
@end

//%PDDM-EXPAND DEFINE_ARRAY(UInt32,uint32_t,int32_t)
// This block of code is generated, do not edit it directly.

static_assert(sizeof(uint32_t) == sizeof(int32_t),"sizes do not match");
@implementation GPBUInt32Array {
  @package
  GPBArrayHelper<int32_t> _helper;
}
- (NSUInteger)count {
  return _helper._count;
}
+ (instancetype)array {
  return [GPBArrayHelper<int32_t>::array(self) autorelease];
}
+ (instancetype)arrayWithValue:(uint32_t)value {
  return [[(GPBUInt32Array*)[self alloc] initWithValues:(uint32_t *)&value count:1] autorelease];
}
+ (instancetype)arrayWithValueArray:(GPBUInt32Array *)array {
  return [[(GPBUInt32Array*)[self alloc] initWithValueArray:array] autorelease];
}
+ (instancetype)arrayWithCapacity:(NSUInteger)count {
  return [[[self alloc] initWithCapacity:count] autorelease];
}
- (instancetype)init {
  self = [super init];
  return self;
}
- (instancetype)initWithValueArray:(GPBUInt32Array *)array {
  return [self initWithValues:(uint32_t *)array->_helper._values count:array->_helper._count];
}
- (instancetype)initWithValues:(const uint32_t[])values count:(NSUInteger)count {
  self = [self init];
  if (self) {
    _helper.initWithValues(self,(int32_t *)values,count);
  }
  return self;
}
- (instancetype)initWithCapacity:(NSUInteger)count {
  self = [self initWithValues:NULL count:0];
  if (self && count) {
  _helper.internalResizeToCapacity(count);
  }
  return self;
}
- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBUInt32Array allocWithZone:zone] initWithValues:(uint32_t *)self->_helper._values count:self->_helper._count];
}
- (void)dealloc {
  NSAssert2(!_autocreator,
         @"%@: Autocreator must be cleared before release, autocreator: %@",
         [self class], _autocreator);
[super dealloc];
}
- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBUInt32Array class]]) {
    return NO;
  }
  return _helper.isEqual(((GPBUInt32Array *)other)->_helper);
}
- (NSUInteger)hash {
  // Follow NSArray's lead, and use the count as the hash.
  return _helper._count;
}
- (NSString *)description {
  return _helper.description(self);
}
- (void)enumerateValuesWithBlock:(void (^)(uint32_t value, NSUInteger idx, BOOL *stop))block {
  [self enumerateValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
}
- (void)enumerateValuesWithOptions:(NSEnumerationOptions)opts
  usingBlock:(void (^)(uint32_t value, NSUInteger idx, BOOL *stop))block {
  void (^block2)(int32_t value, NSUInteger idx, BOOL *stop) = ^(int32_t value, NSUInteger idx, BOOL *stop) {
    block((uint32_t)value,idx,stop);
  };
  _helper.enumerateValuesWithOptions(opts,block2);
}
- (uint32_t)valueAtIndex:(NSUInteger)index {
  return (uint32_t)_helper.valueAtIndex(index);
}
- (void)addValue:(uint32_t)value {
[self addValues:&value count:1];
}
- (void)addValues:(const uint32_t [])values count:(NSUInteger)count {
_helper.addValues((int32_t *)values,count);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}
- (void)insertValue:(uint32_t)value atIndex:(NSUInteger)index {
  _helper.insertValue((int32_t)value,index);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)replaceValueAtIndex:(NSUInteger)index withValue:(uint32_t)value {
  _helper.replaceValueAtIndex(index,(int32_t)value);
}
- (void)addValuesFromArray:(GPBUInt32Array *)array {
  [self addValues:(uint32_t *)array->_helper._values count:array->_helper._count];
}
- (void)removeValueAtIndex:(NSUInteger)index {
  _helper.removeValueAtIndex(index);
}
- (void)removeAll {
  _helper.removeAll();
}
- (void)exchangeValueAtIndex:(NSUInteger)idx1
  withValueAtIndex:(NSUInteger)idx2 {
    _helper.exchangeValueAtIndex(idx1,idx2);
}
@end

//%PDDM-EXPAND DEFINE_ARRAY(UInt64,uint64_t,int64_t)
// This block of code is generated, do not edit it directly.

static_assert(sizeof(uint64_t) == sizeof(int64_t),"sizes do not match");
@implementation GPBUInt64Array {
  @package
  GPBArrayHelper<int64_t> _helper;
}
- (NSUInteger)count {
  return _helper._count;
}
+ (instancetype)array {
  return [GPBArrayHelper<int64_t>::array(self) autorelease];
}
+ (instancetype)arrayWithValue:(uint64_t)value {
  return [[(GPBUInt64Array*)[self alloc] initWithValues:(uint64_t *)&value count:1] autorelease];
}
+ (instancetype)arrayWithValueArray:(GPBUInt64Array *)array {
  return [[(GPBUInt64Array*)[self alloc] initWithValueArray:array] autorelease];
}
+ (instancetype)arrayWithCapacity:(NSUInteger)count {
  return [[[self alloc] initWithCapacity:count] autorelease];
}
- (instancetype)init {
  self = [super init];
  return self;
}
- (instancetype)initWithValueArray:(GPBUInt64Array *)array {
  return [self initWithValues:(uint64_t *)array->_helper._values count:array->_helper._count];
}
- (instancetype)initWithValues:(const uint64_t[])values count:(NSUInteger)count {
  self = [self init];
  if (self) {
    _helper.initWithValues(self,(int64_t *)values,count);
  }
  return self;
}
- (instancetype)initWithCapacity:(NSUInteger)count {
  self = [self initWithValues:NULL count:0];
  if (self && count) {
  _helper.internalResizeToCapacity(count);
  }
  return self;
}
- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBUInt64Array allocWithZone:zone] initWithValues:(uint64_t *)self->_helper._values count:self->_helper._count];
}
- (void)dealloc {
  NSAssert2(!_autocreator,
         @"%@: Autocreator must be cleared before release, autocreator: %@",
         [self class], _autocreator);
[super dealloc];
}
- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBUInt64Array class]]) {
    return NO;
  }
  return _helper.isEqual(((GPBUInt64Array *)other)->_helper);
}
- (NSUInteger)hash {
  // Follow NSArray's lead, and use the count as the hash.
  return _helper._count;
}
- (NSString *)description {
  return _helper.description(self);
}
- (void)enumerateValuesWithBlock:(void (^)(uint64_t value, NSUInteger idx, BOOL *stop))block {
  [self enumerateValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
}
- (void)enumerateValuesWithOptions:(NSEnumerationOptions)opts
  usingBlock:(void (^)(uint64_t value, NSUInteger idx, BOOL *stop))block {
  void (^block2)(int64_t value, NSUInteger idx, BOOL *stop) = ^(int64_t value, NSUInteger idx, BOOL *stop) {
    block((uint64_t)value,idx,stop);
  };
  _helper.enumerateValuesWithOptions(opts,block2);
}
- (uint64_t)valueAtIndex:(NSUInteger)index {
  return (uint64_t)_helper.valueAtIndex(index);
}
- (void)addValue:(uint64_t)value {
[self addValues:&value count:1];
}
- (void)addValues:(const uint64_t [])values count:(NSUInteger)count {
_helper.addValues((int64_t *)values,count);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}
- (void)insertValue:(uint64_t)value atIndex:(NSUInteger)index {
  _helper.insertValue((int64_t)value,index);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)replaceValueAtIndex:(NSUInteger)index withValue:(uint64_t)value {
  _helper.replaceValueAtIndex(index,(int64_t)value);
}
- (void)addValuesFromArray:(GPBUInt64Array *)array {
  [self addValues:(uint64_t *)array->_helper._values count:array->_helper._count];
}
- (void)removeValueAtIndex:(NSUInteger)index {
  _helper.removeValueAtIndex(index);
}
- (void)removeAll {
  _helper.removeAll();
}
- (void)exchangeValueAtIndex:(NSUInteger)idx1
  withValueAtIndex:(NSUInteger)idx2 {
    _helper.exchangeValueAtIndex(idx1,idx2);
}
@end

//%PDDM-EXPAND-END (7 expansions)



#pragma mark - NSArray Subclass

@implementation GPBAutocreatedArray {
  NSMutableArray *_array;
}

- (void)dealloc {
  NSAssert2(!_autocreator,
           @"%@: Autocreator must be cleared before release, autocreator: %@",
           [self class], _autocreator);
  [_array release];
  [super dealloc];
}

#pragma mark Required NSArray overrides

- (NSUInteger)count {
  return [_array count];
}

- (id)objectAtIndex:(NSUInteger)idx {
  return [_array objectAtIndex:idx];
}

#pragma mark Required NSMutableArray overrides

// Only need to call GPBAutocreatedArrayModified() when adding things since
// we only autocreate empty arrays.

- (void)insertObject:(id)anObject atIndex:(NSUInteger)idx {
  if (_array == nil) {
    _array = [[NSMutableArray alloc] init];
  }
  [_array insertObject:anObject atIndex:idx];
  
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)removeObject:(id)anObject {
  [_array removeObject:anObject];
}

- (void)removeObjectAtIndex:(NSUInteger)idx {
  [_array removeObjectAtIndex:idx];
}

- (void)addObject:(id)anObject {
  if (_array == nil) {
    _array = [[NSMutableArray alloc] init];
  }
  [_array addObject:anObject];
  
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)removeLastObject {
  [_array removeLastObject];
}

- (void)replaceObjectAtIndex:(NSUInteger)idx withObject:(id)anObject {
  [_array replaceObjectAtIndex:idx withObject:anObject];
}

#pragma mark Extra things hooked

- (id)copyWithZone:(NSZone *)zone {
  if (_array == nil) {
    return [[NSMutableArray allocWithZone:zone] init];
  }
  return [_array copyWithZone:zone];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
  if (_array == nil) {
    return [[NSMutableArray allocWithZone:zone] init];
  }
  return [_array mutableCopyWithZone:zone];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained [])buffer
                                    count:(NSUInteger)len {
  return [_array countByEnumeratingWithState:state objects:buffer count:len];
}

- (void)enumerateObjectsUsingBlock:(void (^)(id obj, NSUInteger idx, BOOL *stop))block {
  [_array enumerateObjectsUsingBlock:block];
}

- (void)enumerateObjectsWithOptions:(NSEnumerationOptions)opts
                         usingBlock:(void (^)(id obj, NSUInteger idx, BOOL *stop))block {
  [_array enumerateObjectsWithOptions:opts usingBlock:block];
}

@end


#pragma mark - Enum

@implementation GPBEnumArray {
  @package
  GPBEnumValidationFunc _validationFunc;
  int32_t *_values;
  NSUInteger _count;
  NSUInteger _capacity;
}

@synthesize count = _count;
@synthesize validationFunc = _validationFunc;

+ (instancetype)array {
  return [[[self alloc] initWithValidationFunction:NULL] autorelease];
}

+ (instancetype)arrayWithValidationFunction:(GPBEnumValidationFunc)func {
  return [[[self alloc] initWithValidationFunction:func] autorelease];
}

+ (instancetype)arrayWithValidationFunction:(GPBEnumValidationFunc)func
                                   rawValue:(int32_t)value {
  return [[[self alloc] initWithValidationFunction:func
                                         rawValues:&value
                                             count:1] autorelease];
}

+ (instancetype)arrayWithValueArray:(GPBEnumArray *)array {
  return [[(GPBEnumArray*)[self alloc] initWithValueArray:array] autorelease];
}

+ (instancetype)arrayWithValidationFunction:(GPBEnumValidationFunc)func
                                   capacity:(NSUInteger)count {
  return [[[self alloc] initWithValidationFunction:func capacity:count] autorelease];
}

- (instancetype)init {
  return [self initWithValidationFunction:NULL];
}

- (instancetype)initWithValueArray:(GPBEnumArray *)array {
  return [self initWithValidationFunction:array->_validationFunc
                                rawValues:array->_values
                                    count:array->_count];
}

- (instancetype)initWithValidationFunction:(GPBEnumValidationFunc)func {
  self = [super init];
  if (self) {
    _validationFunc = (func != NULL ? func : ArrayDefault_IsValidValue);
  }
  return self;
}

- (instancetype)initWithValidationFunction:(GPBEnumValidationFunc)func
                                 rawValues:(const int32_t [])values
                                     count:(NSUInteger)count {
  self = [self initWithValidationFunction:func];
  if (self) {
    if (count && values) {
      _values = (int32_t *)reallocf(_values, count * sizeof(int32_t));
      if (_values != NULL) {
        _capacity = count;
        memcpy(_values, values, count * sizeof(int32_t));
        _count = count;
      } else {
        [self release];
        [NSException raise:NSMallocException
                    format:@"Failed to allocate %lu bytes",
         (unsigned long)(count * sizeof(int32_t))];
      }
    }
  }
  return self;
}

- (instancetype)initWithValidationFunction:(GPBEnumValidationFunc)func
                                  capacity:(NSUInteger)count {
  self = [self initWithValidationFunction:func];
  if (self && count) {
    [self internalResizeToCapacity:count];
  }
  return self;
}

- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBEnumArray allocWithZone:zone]
          initWithValidationFunction:_validationFunc
          rawValues:_values
          count:_count];
}


- (void)dealloc {
  NSAssert2(!_autocreator,
           @"%@: Autocreator must be cleared before release, autocreator: %@",
           [self class], _autocreator);
  free(_values);
  [super dealloc];
}

- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBEnumArray class]]) {
    return NO;
  }
  GPBEnumArray *otherArray = other;
  return (_count == otherArray->_count
          && memcmp(_values, otherArray->_values, (_count * sizeof(int32_t))) == 0);
}

- (NSUInteger)hash {
  // Follow NSArray's lead, and use the count as the hash.
  return _count;
}

- (NSString *)description {
  NSMutableString *result = [NSMutableString stringWithFormat:@"<%@ %p> { ", [self class], self];
  for (NSUInteger i = 0, count = _count; i < count; ++i) {
    if (i == 0) {
      [result appendFormat:@"%d", _values[i]];
    } else {
      [result appendFormat:@", %d", _values[i]];
    }
  }
  [result appendFormat:@" }"];
  return result;
}

- (void)enumerateRawValuesWithBlock:(void (^)(int32_t value, NSUInteger idx, BOOL *stop))block {
  [self enumerateRawValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
}

- (void)enumerateRawValuesWithOptions:(NSEnumerationOptions)opts
                           usingBlock:(void (^)(int32_t value, NSUInteger idx, BOOL *stop))block {
  // NSEnumerationConcurrent isn't currently supported (and Apple's docs say that is ok).
  BOOL stop = NO;
  if ((opts & NSEnumerationReverse) == 0) {
    for (NSUInteger i = 0, count = _count; i < count; ++i) {
      block(_values[i], i, &stop);
      if (stop) break;
    }
  } else if (_count > 0) {
    for (NSUInteger i = _count; i > 0; --i) {
      block(_values[i - 1], (i - 1), &stop);
      if (stop) break;
    }
  }
}

- (int32_t)valueAtIndex:(NSUInteger)index {

  if (index >= _count) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)index, (unsigned long)_count];
  }
  int32_t result = _values[index];
  if (!_validationFunc(result)) {
    result = kGPBUnrecognizedEnumeratorValue;
  }
  return result;
}

- (int32_t)rawValueAtIndex:(NSUInteger)index {

  if (index >= _count) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)index, (unsigned long)_count];
  }
  return _values[index];
}

- (void)enumerateValuesWithBlock:(void (^)(int32_t value, NSUInteger idx, BOOL *stop))block {
  [self enumerateValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
}

- (void)enumerateValuesWithOptions:(NSEnumerationOptions)opts
                        usingBlock:(void (^)(int32_t value, NSUInteger idx, BOOL *stop))block {
  // NSEnumerationConcurrent isn't currently supported (and Apple's docs say that is ok).
  BOOL stop = NO;
  GPBEnumValidationFunc func = _validationFunc;
  if ((opts & NSEnumerationReverse) == 0) {
    int32_t *scan = _values;
    int32_t *end = scan + _count;
    for (NSUInteger i = 0; scan < end; ++i, ++scan) {
      int32_t value = *scan;
      if (!func(value)) {
        value = kGPBUnrecognizedEnumeratorValue;
      }
      block(value, i, &stop);
      if (stop) break;
    }
  } else if (_count > 0) {
    int32_t *end = _values;
    int32_t *scan = end + (_count - 1);
    for (NSUInteger i = (_count - 1); scan >= end; --i, --scan) {
      int32_t value = *scan;
      if (!func(value)) {
        value = kGPBUnrecognizedEnumeratorValue;
      }
      block(value, i, &stop);
      if (stop) break;
    }
  }
}


- (void)internalResizeToCapacity:(NSUInteger)newCapacity {
  _values = (int32_t *)reallocf(_values, newCapacity * sizeof(int32_t));
  if (_values == NULL) {
    _capacity = 0;
    _count = 0;
    [NSException raise:NSMallocException
                format:@"Failed to allocate %lu bytes",
     (unsigned long)(newCapacity * sizeof(int32_t))];
  }
  _capacity = newCapacity;
}

- (void)addRawValue:(int32_t)value {
  [self addRawValues:&value count:1];
}

- (void)addRawValues:(const int32_t [])values count:(NSUInteger)count {
  if (values == NULL || count == 0) return;
  NSUInteger initialCount = _count;
  NSUInteger newCount = initialCount + count;
  if (newCount > _capacity) {
    [self internalResizeToCapacity:CapacityFromCount(newCount)];
  }
  _count = newCount;
  memcpy(&_values[initialCount], values, count * sizeof(int32_t));
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)insertRawValue:(int32_t)value atIndex:(NSUInteger)index {
  if (index >= _count + 1) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)index, (unsigned long)_count + 1];
  }
  NSUInteger initialCount = _count;
  NSUInteger newCount = initialCount + 1;
  if (newCount > _capacity) {
    [self internalResizeToCapacity:CapacityFromCount(newCount)];
  }
  _count = newCount;
  if (index != initialCount) {
    memmove(&_values[index + 1], &_values[index], (initialCount - index) * sizeof(int32_t));
  }
  _values[index] = value;
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)replaceValueAtIndex:(NSUInteger)index withRawValue:(int32_t)value {
  if (index >= _count) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)index, (unsigned long)_count];
  }
  _values[index] = value;
}

- (void)addRawValuesFromArray:(GPBEnumArray *)array {
  [self addRawValues:array->_values count:array->_count];
}

- (void)removeValueAtIndex:(NSUInteger)index {
  if (index >= _count) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)index, (unsigned long)_count];
  }
  NSUInteger newCount = _count - 1;
  if (index != newCount) {
    memmove(&_values[index], &_values[index + 1], (newCount - index) * sizeof(int32_t));
  }
  _count = newCount;
  if ((newCount + (2 * kChunkSize)) < _capacity) {
    [self internalResizeToCapacity:CapacityFromCount(newCount)];
  }
}

- (void)removeAll {
  _count = 0;
  if ((0 + (2 * kChunkSize)) < _capacity) {
    [self internalResizeToCapacity:CapacityFromCount(0)];
  }
}

- (void)exchangeValueAtIndex:(NSUInteger)idx1
            withValueAtIndex:(NSUInteger)idx2 {
  if (idx1 >= _count) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)idx1, (unsigned long)_count];
  }
  if (idx2 >= _count) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)idx2, (unsigned long)_count];
  }
  int32_t temp = _values[idx1];
  _values[idx1] = _values[idx2];
  _values[idx2] = temp;
}

- (void)addValue:(int32_t)value {
  [self addValues:&value count:1];
}

- (void)addValues:(const int32_t [])values count:(NSUInteger)count {
  if (values == NULL || count == 0) return;
  GPBEnumValidationFunc func = _validationFunc;
  for (NSUInteger i = 0; i < count; ++i) {
    if (!func(values[i])) {
      [NSException raise:NSInvalidArgumentException
                  format:@"%@: Attempt to set an unknown enum value (%d)",
       [self class], values[i]];
    }
  }
  NSUInteger initialCount = _count;
  NSUInteger newCount = initialCount + count;
  if (newCount > _capacity) {
    [self internalResizeToCapacity:CapacityFromCount(newCount)];
  }
  _count = newCount;
  memcpy(&_values[initialCount], values, count * sizeof(int32_t));
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)insertValue:(int32_t)value atIndex:(NSUInteger)index {
  if (index >= _count + 1) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)index, (unsigned long)_count + 1];
  }
  if (!_validationFunc(value)) {
    [NSException raise:NSInvalidArgumentException
                format:@"%@: Attempt to set an unknown enum value (%d)",
     [self class], value];
  }
  NSUInteger initialCount = _count;
  NSUInteger newCount = initialCount + 1;
  if (newCount > _capacity) {
    [self internalResizeToCapacity:CapacityFromCount(newCount)];
  }
  _count = newCount;
  if (index != initialCount) {
    memmove(&_values[index + 1], &_values[index], (initialCount - index) * sizeof(int32_t));
  }
  _values[index] = value;
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)replaceValueAtIndex:(NSUInteger)index withValue:(int32_t)value {
  if (index >= _count) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)index, (unsigned long)_count];
  }
  if (!_validationFunc(value)) {
    [NSException raise:NSInvalidArgumentException
                format:@"%@: Attempt to set an unknown enum value (%d)",
     [self class], value];
  }
  _values[index] = value;
}
@end


#pragma clang diagnostic pop
