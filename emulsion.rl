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
  array_marker = "\t";
  object_marker = 0x0A;
  xml_marker = 0x0B;
  byte_array_marker = "\f";
  undefined_type = undefined_marker;
  string_type = string_marker UTF_8_vr;
  integer_type = integer_marker U29;
  U29O_traits = U29;
  class_name =  UTF_8_vr;
  value_type = undefined_marker | null_marker | false_marker | true_marker | integer_type | string_type;
  
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
    np = parseInteger(fpc, &length);
    length = length >> 1;
    fexec np;
  }

  action parse_string {
   *result = rb_str_new(fpc, length);
  }

main:= U29S_value >parse_length (UTF8_char+ >parse_string);
}%%
static char *parseString(char *p, char *pe, VALUE *result) {
  int cs = EVIL;
  unsigned long length = 0;
  char *np;

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
    unsigned long flag;
    char *np = parseInteger(fpc, &flag);
    unsigned char isDynamic = (flag & 0x08) != 0 ? 1 : 0;
    if(isDynamic == 1) {
      *value = rb_hash_new();
    }
    fexec np;
  }

  action parseClassName {
  }

  action parseMemberName {
    char *np = parseString(fpc, pe, &memberName);
    fexec np;
    fnext v_type;
  }

  action parseType {
    char *np = parseAmf(fpc, pe, &memberValue);
    rb_hash_aset(*value, rb_str_intern(memberName), memberValue);
    fexec np;
    fnext member;
  }

  member := (U29S_value)>parseMemberName;
  v_type := value_type >parseType;
  object:= U29O_traits >parseDynamic class_name >parseClassName (U29S_value)> {fhold; fgoto member;};
}%%

static char *parseObject(char *p, char *pe, VALUE *value) {
  int cs = EVIL;
  unsigned char isDynamic;
  VALUE memberName = Qnil;
  VALUE memberValue = Qnil;
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
            object_marker >parse_object)%*exit;

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
