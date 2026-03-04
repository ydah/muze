#include "ruby.h"

static VALUE mMuze;
static VALUE mNative;

static VALUE native_frame_slices(VALUE self, VALUE rb_signal, VALUE rb_frame_length, VALUE rb_hop_length) {
  Check_Type(rb_signal, T_ARRAY);
  const long signal_length = RARRAY_LEN(rb_signal);
  const long frame_length = NUM2LONG(rb_frame_length);
  const long hop_length = NUM2LONG(rb_hop_length);

  if (frame_length <= 0 || hop_length <= 0) {
    rb_raise(rb_eArgError, "frame_length and hop_length must be positive");
  }

  if (signal_length <= frame_length) {
    VALUE frame = rb_ary_new2(frame_length);
    for (long i = 0; i < frame_length; i++) {
      VALUE sample = i < signal_length ? rb_ary_entry(rb_signal, i) : DBL2NUM(0.0);
      rb_ary_push(frame, sample);
    }
    VALUE single = rb_ary_new();
    rb_ary_push(single, frame);
    return single;
  }

  const long frame_count = ((signal_length - frame_length) / hop_length) + 1;
  VALUE frames = rb_ary_new2(frame_count);

  for (long frame_idx = 0; frame_idx < frame_count; frame_idx++) {
    long start = frame_idx * hop_length;
    VALUE frame = rb_ary_new2(frame_length);

    for (long i = 0; i < frame_length; i++) {
      rb_ary_push(frame, rb_ary_entry(rb_signal, start + i));
    }

    rb_ary_push(frames, frame);
  }

  return frames;
}

static int cmp_double(const void *a, const void *b) {
  const double left = *(const double *)a;
  const double right = *(const double *)b;
  if (left < right) return -1;
  if (left > right) return 1;
  return 0;
}

static VALUE native_median1d(VALUE self, VALUE rb_values) {
  Check_Type(rb_values, T_ARRAY);
  const long count = RARRAY_LEN(rb_values);
  if (count == 0) return DBL2NUM(0.0);

  double *values = ALLOC_N(double, count);

  for (long i = 0; i < count; i++) {
    values[i] = NUM2DBL(rb_ary_entry(rb_values, i));
  }

  qsort(values, count, sizeof(double), cmp_double);
  const double median = values[count / 2];
  xfree(values);
  return DBL2NUM(median);
}

void Init_muze_ext(void) {
  mMuze = rb_define_module("Muze");
  mNative = rb_define_module_under(mMuze, "Native");

  rb_define_singleton_method(mNative, "frame_slices", native_frame_slices, 3);
  rb_define_singleton_method(mNative, "median1d", native_median1d, 1);
}
