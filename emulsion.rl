#include <stdio.h>
#include <string.h>
#include <time.h>
#include "ruby.h"
#include "emulsion.h"


#define EVIL 0x666
static VALUE parse_string(char *p, char *pe);
static VALUE parse(VALUE self, VALUE amf);
static char *parseAmf(char *p, char *pe, VALUE *val);
static VALUE cEmulsion;

static VALUE stringRefs[100];
static int stringRefsTop = 0;

static VALUE objectRefs[100];
static int objectRefsTop = 0;


%%{
  machine amf_common;

  U29_1 = 0x00..0x7f;
  U29_2 = 0x80..0xff 0x00..0x7f;
  U29_3 = 0x80..0xff 0x80..0xff 0x00..0x7f;
  U29_4 = 0x80..0xff 0x80..0xff 0x80..0xff 0xff..0x00;
  U29 = U29_1 | U29_2 | U29_3 | U29_4;
  UTF8_1 = 0x00..0x7f;
  UTF8_tail = 0x80..0xbf;
  UTF8_2 = 0xc2..0xdf UTF8_tail;
  UTF8_3 = ( 0xe0 0xa0..0xbf UTF8_tail ) | ( 0xe1..0xec UTF8_tail{2} ) | ( 0xed 0x80..0x9f UTF8_tail ) | ( 0xee..0xef UTF8_tail{2} );
  UTF8_4 = ( 0xf0 0x90..0xbf UTF8_tail{2} ) | ( 0xf1..0xf3 UTF8_tail{3} ) | ( 0xf4 0x80..0x8f UTF8_tail{2} );
  UTF8_char = UTF8_1 | UTF8_2 | UTF8_3 | UTF8_4;
  U29S_ref = U29;
  U29S_value = U29;
  U29A_value = U29;
  UTF_8_empty = 0x01;
  UTF_8_vr = U29S_ref | ( U29S_value UTF8_char* );
  undefined_marker = "\0";
  null_marker = 0x01;
  false_marker = 0x02;
  true_marker = 0x03;
  integer_marker = 0x04;
  double_marker = 0x05;
  string_marker = 0x06;
  xml_doc_marker = 0x07;
  date_marker = "\b";
  array_marker = 0x09;
  object_marker = 0x0A;
  xml_marker = 0x0B;
  byte_array_marker = "\f";
  undefined_type = undefined_marker;
  string_type = string_marker UTF_8_vr;
  integer_type = integer_marker U29;
  U29O_traits = U29;
  class_name =  UTF_8_vr;
  value_type = undefined_marker | null_marker | false_marker | true_marker | integer_type | double_marker | string_type | xml_doc_marker | date_marker | array_marker | object_marker | xml_marker | byte_array_marker;
}%%

static char *parseInteger(char *p, unsigned long *result) {
  int n = 0;
  unsigned char b = 0;
  b = *p;

  while((b & 0x80) != 0 && n < 3) {
    *result = *result << 7;
    *result = *result | (b & 0x7f);
    ++p;
    b = *p;
    ++n;
  }

  if (n < 3) {
    *result = *result<< 7;
    *result = *result| b;
  }
  else {
    //Use all 8 bits from the 4th byte
    *result = *result << 8;
    *result = *result | b;
    //Check if the integer should be negative
    if (*result > 268435455) {
      *result -= (1 << 29);
    }
  }

  //Increment the pointet to point to the next characer to process
  if(n == 0) {
    ++p;
  }
  return p;
}

static char *parseDouble(char *p, double *result) {

  union doubleOrByte {
    char buffer[sizeof(double)];
    double val;
  } converter;

  int i = 0;

  for(i = 7; i >= 0; i--) {
    converter.buffer[i] = *p;
    ++p;
  }

  *result = converter.val;
  return p;
}


%%{
  machine amf_string;
  write data;
  include amf_common;

  action parse_length {
    if(*fpc & 0x01 == 1) {
      np = parseInteger(fpc, &length);
      length = length >> 1;
      fexec np;
    }
    else {
      *fpc = *fpc > 1;
      np = parseInteger(fpc, &stringIndex);
      *result = stringRefs[stringIndex];
      fexec np;
      fbreak;
    }
  }

  action parse_string {
   *result = rb_str_new(fpc, length);
   stringRefs[stringRefsTop] = *result;
   stringRefsTop++;
  }

main:= U29S_value >parse_length (UTF8_char+ >parse_string);
}%%
static char *parseString(char *p, char *pe, VALUE *result) {
  int cs = EVIL;
  unsigned long length = 0;
  char *np;
  unsigned long stringIndex = 0;

  %% write init;
  %% write exec;

  return np+length;
}

static char *parseDate(char *p, VALUE *result) {
  p++;
  p++;

  union timeOrByte {
    char buffer[sizeof(time_t)];
    time_t val;
  } converter;

  int i = 0;

  for(i = 7; i >= 0; i--) {
    converter.buffer[i] = *p;
    ++p;
  }

  *result = rb_time_new(0, converter.val);
  return p;
}

static char *parseXml(char *p, VALUE *result) {
  *p = *p >> 1;
  unsigned long length = 0;
  char *np = parseInteger(p, &length);
  *result = rb_str_new(np, length);
  return np+length;
}

%%{
  machine amf_object;
  write data;
  include amf_common;

  action parseDynamic {

    if(*fpc & 0x01 == 1) {
      unsigned long flag;
      char *np = parseInteger(fpc, &flag);
      isDynamic = (flag & 0x08) != 0 ? 1 : 0;
      fexec np;
    }
    else {
      *fpc = *fpc > 1;
      np = parseInteger(fpc, &objectIndex);
      *value = objectRefs[objectIndex];
      fexec np;
      fbreak;
    }
  }

  action parseClassName {
    if(*fpc == 0x01) {
      *value = rb_hash_new();
      fpc++;
      fexec fpc;
    }
    else {
      isConcrete = 1;
      char *np = parseString(fpc, pe, &className);

      VALUE class = rb_funcall(cEmulsion, classForId, 1, className);

      if(class == Qnil) {
        ID class_id = rb_intern(StringValuePtr(className));
        class = rb_const_get(rb_cObject, class_id);
      }

      VALUE argv[0];
      *value = rb_class_new_instance(0, argv, class);
      fexec np;
    }
    objectRefs[objectRefsTop] = *value;
    objectRefsTop ++;
  }

  action parseMemberName {
    if(*fpc != 0x01) {
      char *np = parseString(fpc, pe, &memberName);
      fexec np;
      fnext v_type;
    }
    else {
      np = fpc+1;
      fexec np;
      fbreak;
    }
  }

  action parseType {
    char *np = parseAmf(fpc, pe, &memberValue);
    if(isConcrete) {
      unsigned long memberNameLen = RSTRING(memberName)->len;
      char instance_var_name[memberNameLen + 1];
      instance_var_name[0] = '\0';
      strncat(instance_var_name, "@", 1);
      strncat(instance_var_name, RSTRING(memberName)->ptr, memberNameLen);
      rb_iv_set(*value, instance_var_name, memberValue);
    }
    else {
      rb_hash_aset(*value, rb_str_intern(memberName), memberValue);
    }

    fexec np;
    fnext member;
  }

  member := (U29S_value)>parseMemberName;
  v_type := value_type >parseType;
  object:= U29O_traits >parseDynamic class_name >parseClassName (U29S_value)> {fhold; fgoto member;};
}%%

static char *parseObject(char *p, char *pe, VALUE *value) {
  int cs = EVIL;
  char *np;
  unsigned long objectIndex = 0;
  VALUE className = Qnil;
  unsigned char isDynamic;
  unsigned char isConcrete = 0;
  VALUE memberName = Qnil;
  VALUE memberValue = Qnil;
  ID classForId = rb_intern("class_for");
  %% write init;
  %% write exec;
  return np;
}


%%{
  machine amf_array;
  write data;
  include amf_common;

  action parseDensePortion {
    *fpc = *fpc >> 1;
    char *np = parseInteger(fpc, &denseLength);
    fexec np;
  }

  action parseEmptyArray {
    //TODO Optimize this so we initialize the ruby array with the parsed values
    *value = rb_ary_new();
    if(denseLength == 0) {
      fbreak;
    }
  }

  action parseType {
    char *np; 
    unsigned long i = 0;
    for(i=0; i < denseLength; i++) {
      np = parseAmf(fpc, pe, &element);
      rb_ary_push(*value, element);
      fpc = np;
    }
    fexec np;
    fbreak;
  }

  main := U29A_value >parseDensePortion (UTF_8_empty >parseEmptyArray) value_type >parseType;
}%%

static char *parseArray(char *p, char *pe, VALUE *value) {
  int cs = EVIL;
  const char *eof = 0;
  unsigned long denseLength = 0;
  VALUE *elements;
  VALUE element;
  %% write init;
  %% write exec;
  return p;
}

%%{
  machine amf;
  write data;
  include amf_common;

  action parse_null {
    *value = Qnil;
    np = fpc+1;
    fbreak;
  }

  action parse_false {
    *value = Qfalse;
    np = fpc+1;
    fbreak;
  }

  action parse_true {
    *value = Qtrue;
    np = fpc+1;
    fbreak;
  }

  action parse_integer {
    fpc++;
    unsigned long intValue = 0;
    np = parseInteger(fpc, &intValue);
    *value = INT2NUM(intValue);
    fbreak;
  }

  action parse_double {
    fpc++;
    double doubleValue = 0.0;
    np = parseDouble(fpc, &doubleValue);
    *value = INT2NUM(doubleValue);
    fbreak;
  }

  action parse_date {
    np = parseDate(fpc, value);
    fbreak;
  }

  action parse_xml {
    fpc++;
    parseXml(fpc, value);
    fbreak;
  }

  action parse_string {
    fpc++;
    np = parseString(fpc, pe, value);
    fbreak;
  }

  action parse_object {
    fpc++;
    np = parseObject(fpc, pe, value);
    fbreak;
  }

  action parse_array {
    fpc++;
    np = parseArray(fpc, pe, value);
    fbreak;
  }

  action exit {
    //fhold; fbreak;
  }

  main := ( null_marker>parse_null |
            string_type> parse_string |
            false_marker>parse_false |
            true_marker>parse_true |
            integer_marker >parse_integer |
            double_marker>parse_double |
            date_marker>parse_date |
            xml_doc_marker>parse_xml |
            xml_marker>parse_xml |
            object_marker >parse_object |
            array_marker >parse_array)%*exit;

}%%
static char *parseAmf(char *p, char *pe, VALUE *value) {
  int cs = EVIL;
  char *np;

  %% write init;
  %% write exec;

  return np;
}

static VALUE parse(VALUE self, VALUE amf) {
  VALUE source = StringValue(amf);
  VALUE value = Qnil;
  long len = RSTRING(source)->len;
  char *p = RSTRING(source)->ptr;
  char *pe = p + len;
  parseAmf(p, pe, &value);
  return value;
}

void Init_emulsion()
{
  cEmulsion = rb_define_class("Emulsion", rb_cObject);
  rb_define_method(cEmulsion, "parse", parse, 1);
}
