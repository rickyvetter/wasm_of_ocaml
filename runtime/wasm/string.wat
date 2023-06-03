(module
   (import "fail" "caml_bound_error" (func $caml_bound_error))
   (import "fail" "caml_invalid_argument"
      (func $caml_invalid_argument (param $arg (ref eq))))
   (import "int32" "caml_copy_int32"
      (func $caml_copy_int32 (param i32) (result (ref eq))))
   (import "int64" "caml_copy_int64"
      (func $caml_copy_int64 (param i64) (result (ref eq))))

   (type $string (array (mut i8)))
   (type $value->value->int
      (func (param (ref eq)) (param (ref eq)) (result i32)))
   (type $value->int
      (func (param (ref eq)) (result i32)))
   (type $custom_operations
      (struct
         (field (ref $string)) ;; identifier
         (field (ref $value->value->int)) ;; compare
         (field (ref null $value->int)) ;; hash
         ;; ZZZ
      ))
   (type $custom (struct (field (ref $custom_operations))))
   (type $int32
      (sub $custom (struct (field (ref $custom_operations)) (field i32))))
   (type $int64
      (sub $custom (struct (field (ref $custom_operations)) (field i64))))

   (export "caml_bytes_equal" (func $caml_string_equal))
   (func $caml_string_equal (export "caml_string_equal")
      (param $p1 (ref eq)) (param $p2 (ref eq)) (result (ref eq))
      (local $s1 (ref $string)) (local $s2 (ref $string))
      (local $len i32) (local $i i32)
      (if (ref.eq (local.get $p1) (local.get $p2))
         (then (return (i31.new (i32.const 1)))))
      (local.set $s1 (ref.cast $string (local.get $p1)))
      (local.set $s2 (ref.cast $string (local.get $p2)))
      (local.set $len (array.len $string (local.get $s1)))
      (if (i32.ne (local.get $len) (array.len $string (local.get $s2)))
         (then (return (i31.new (i32.const 0)))))
      (local.set $i (i32.const 0))
      (loop $loop
         (if (i32.lt_s (local.get $i) (local.get $len))
            (then
               (if (i32.ne (array.get_u $string (local.get $s1) (local.get $i))
                           (array.get_u $string (local.get $s2) (local.get $i)))
                  (then (return (i31.new (i32.const 0)))))
               (local.set $i (i32.add (local.get $i) (i32.const 1)))
               (br $loop))))
      (i31.new (i32.const 1)))

   (export "caml_bytes_notequal" (func $caml_string_notequal))
   (func $caml_string_notequal (export "caml_string_notequal")
      (param $p1 (ref eq)) (param $p2 (ref eq)) (result (ref eq))
      (return
         (i31.new (i32.eqz (i31.get_u (ref.cast i31
            (call $caml_string_equal (local.get $p1) (local.get $p2))))))))

   (func $string_compare
      (param $p1 (ref eq)) (param $p2 (ref eq)) (result i32)
      (local $s1 (ref $string)) (local $s2 (ref $string))
      (local $l1 i32) (local $l2 i32) (local $len i32) (local $i i32)
      (local $c1 i32) (local $c2 i32)
      (if (ref.eq (local.get $p1) (local.get $p2))
         (then (return (i32.const 0))))
      (local.set $s1 (ref.cast $string (local.get $p1)))
      (local.set $s2 (ref.cast $string (local.get $p2)))
      (local.set $l1 (array.len $string (local.get $s1)))
      (local.set $l2 (array.len $string (local.get $s2)))
      (local.set $len (select (local.get $l1) (local.get $l2)
                          (i32.le_u (local.get $l1) (local.get $l2))))
      (local.set $i (i32.const 0))
      (loop $loop
         (if (i32.lt_s (local.get $i) (local.get $len))
            (then
               (local.set $c1
                  (array.get_u $string (local.get $s1) (local.get $i)))
               (local.set $c2
                  (array.get_u $string (local.get $s2) (local.get $i)))
               (if (i32.lt_u (local.get $c1) (local.get $c2))
                  (then (return (i32.const -1))))
               (if (i32.gt_u (local.get $c1) (local.get $c2))
                  (then (return (i32.const 1))))
               (local.set $i (i32.add (local.get $i) (i32.const 1)))
               (br $loop))))
      (if (i32.lt_u (local.get $l1) (local.get $l2))
         (then (return (i32.const -1))))
      (if (i32.gt_u (local.get $l1) (local.get $l2))
         (then (return (i32.const 1))))
      (i32.const 0))

   (export "caml_bytes_compare" (func $caml_string_compare))
   (func $caml_string_compare (export "caml_string_compare")
      (param (ref eq)) (param (ref eq)) (result (ref eq))
      (i31.new (call $string_compare (local.get 0) (local.get 1))))

   (export "caml_bytes_lessequal" (func $caml_string_lessequal))
   (func $caml_string_lessequal (export "caml_string_lessequal")
      (param (ref eq)) (param (ref eq)) (result (ref eq))
      (i31.new (i32.le_s (call $string_compare (local.get 0) (local.get 1))
                         (i32.const 0))))

   (export "caml_bytes_lessthan" (func $caml_string_lessthan))
   (func $caml_string_lessthan (export "caml_string_lessthan")
      (param (ref eq)) (param (ref eq)) (result (ref eq))
      (i31.new (i32.lt_s (call $string_compare (local.get 0) (local.get 1))
                         (i32.const 0))))

   (export "caml_bytes_greaterequal" (func $caml_string_greaterequal))
   (func $caml_string_greaterequal (export "caml_string_greaterequal")
      (param (ref eq)) (param (ref eq)) (result (ref eq))
      (i31.new (i32.ge_s (call $string_compare (local.get 0) (local.get 1))
                         (i32.const 0))))

   (export "caml_bytes_greaterthan" (func $caml_string_greaterthan))
   (func $caml_string_greaterthan (export "caml_string_greaterthan")
      (param (ref eq)) (param (ref eq)) (result (ref eq))
      (i31.new (i32.gt_s (call $string_compare (local.get 0) (local.get 1))
                         (i32.const 0))))

   (export "caml_bytes_of_string" (func $caml_string_of_bytes))
   (func $caml_string_of_bytes (export "caml_string_of_bytes")
      (param $v (ref eq)) (result (ref eq))
      (local.get $v))

   (data $Bytes_create "Bytes.create")

   (func (export "caml_create_bytes")
      (param $len (ref eq)) (result (ref eq))
      (local $l i32)
      (local.set $l (i31.get_s (ref.cast i31 (local.get $len))))
      (if (i32.lt_s (local.get $l) (i32.const 0))
         (then
            (call $caml_invalid_argument
               (array.new_data $string $Bytes_create
                               (i32.const 0) (i32.const 12)))))
      (array.new $string (i32.const 0) (local.get $l)))

   (export "caml_blit_bytes" (func $caml_blit_string))
   (func $caml_blit_string (export "caml_blit_string")
      (param $v1 (ref eq)) (param $i1 (ref eq))
      (param $v2 (ref eq)) (param $i2 (ref eq))
      (param $n (ref eq)) (result (ref eq))
      (array.copy $string $string
         (ref.cast $string (local.get $v2))
         (i31.get_s (ref.cast i31 (local.get $i2)))
         (ref.cast $string (local.get $v1))
         (i31.get_s (ref.cast i31 (local.get $i1)))
         (i31.get_s (ref.cast i31 (local.get $n))))
      (i31.new (i32.const 0)))

   (func (export "caml_fill_bytes")
      (param $v (ref eq)) (param $offset (ref eq))
      (param $len (ref eq)) (param $init (ref eq))
      (result (ref eq))
(;ZZZ V8 bug
      (array.fill $string (ref.cast $string (local.get $v))
         (i31.get_u (ref.cast i31 (local.get $offset)))
         (i31.get_u (ref.cast i31 (local.get $init)))
         (i31.get_u (ref.cast i31 (local.get $len))))
;)
      (local $s (ref $string)) (local $i i32) (local $limit i32) (local $c i32)
      (local.set $s (ref.cast $string (local.get $v)))
      (local.set $i (i31.get_u (ref.cast i31 (local.get $offset))))
      (local.set $limit
         (i32.add (local.get $i) (i31.get_u (ref.cast i31 (local.get $len)))))
      (local.set $c (i31.get_u (ref.cast i31 (local.get $init))))
      (loop $loop
         (if (i32.lt_u (local.get $i) (local.get $limit))
            (then
               (array.set $string (local.get $s) (local.get $i) (local.get $c))
               (local.set $i (i32.add (local.get $i) (i32.const 1)))
               (br $loop))))
      (i31.new (i32.const 0)))

   (export "caml_string_get16" (func $caml_bytes_get16))
   (func $caml_bytes_get16 (export "caml_bytes_get16")
      (param $v (ref eq)) (param $i (ref eq)) (result (ref eq))
      (local $s (ref $string)) (local $p i32)
      (local.set $s (ref.cast $string (local.get $v)))
      (local.set $p (i31.get_s (ref.cast i31 (local.get $i))))
      (if (i32.lt_s (local.get $p) (i32.const 0))
         (then (call $caml_bound_error)))
      (if (i32.ge_u (i32.add (local.get $p) (i32.const 1))
                    (array.len (local.get $s)))
         (then (call $caml_bound_error)))
      (i31.new (i32.or
                  (array.get_u $string (local.get $s) (local.get $p))
                  (i32.shl (array.get_u $string (local.get $s)
                              (i32.add (local.get $p) (i32.const 1)))
                           (i32.const 8)))))

   (export "caml_string_get32" (func $caml_bytes_get32))
   (func $caml_bytes_get32 (export "caml_bytes_get32")
      (param $v (ref eq)) (param $i (ref eq)) (result (ref eq))
      (local $s (ref $string)) (local $p i32)
      (local.set $s (ref.cast $string (local.get $v)))
      (local.set $p (i31.get_s (ref.cast i31 (local.get $i))))
      (if (i32.lt_s (local.get $p) (i32.const 0))
         (then (call $caml_bound_error)))
      (if (i32.ge_u (i32.add (local.get $p) (i32.const 3))
                    (array.len (local.get $s)))
         (then (call $caml_bound_error)))
      (return_call $caml_copy_int32
         (i32.or
            (i32.or
               (array.get_u $string (local.get $s) (local.get $p))
               (i32.shl (array.get_u $string (local.get $s)
                           (i32.add (local.get $p) (i32.const 1)))
                        (i32.const 8)))
            (i32.or
               (i32.shl (array.get_u $string (local.get $s)
                           (i32.add (local.get $p) (i32.const 2)))
                        (i32.const 16))
               (i32.shl (array.get_u $string (local.get $s)
                           (i32.add (local.get $p) (i32.const 3)))
                        (i32.const 24))))))

   (export "caml_string_get64" (func $caml_bytes_get64))
   (func $caml_bytes_get64 (export "caml_bytes_get64")
      (param $v (ref eq)) (param $i (ref eq)) (result (ref eq))
      (local $s (ref $string)) (local $p i32)
      (local.set $s (ref.cast $string (local.get $v)))
      (local.set $p (i31.get_s (ref.cast i31 (local.get $i))))
      (if (i32.lt_s (local.get $p) (i32.const 0))
         (then (call $caml_bound_error)))
      (if (i32.ge_u (i32.add (local.get $p) (i32.const 7))
                    (array.len (local.get $s)))
         (then (call $caml_bound_error)))
      (return_call $caml_copy_int64
         (i64.or
            (i64.or
               (i64.or
                  (i64.extend_i32_u
                     (array.get_u $string (local.get $s) (local.get $p)))
                  (i64.shl (i64.extend_i32_u
                              (array.get_u $string (local.get $s)
                                 (i32.add (local.get $p) (i32.const 1))))
                           (i64.const 8)))
               (i64.or
                  (i64.shl (i64.extend_i32_u
                              (array.get_u $string (local.get $s)
                                 (i32.add (local.get $p) (i32.const 2))))
                           (i64.const 16))
                  (i64.shl (i64.extend_i32_u
                              (array.get_u $string (local.get $s)
                                 (i32.add (local.get $p) (i32.const 3))))
                           (i64.const 24))))
            (i64.or
               (i64.or
                  (i64.shl (i64.extend_i32_u
                              (array.get_u $string (local.get $s)
                                 (i32.add (local.get $p) (i32.const 4))))
                           (i64.const 32))
                  (i64.shl (i64.extend_i32_u
                              (array.get_u $string (local.get $s)
                                 (i32.add (local.get $p) (i32.const 5))))
                           (i64.const 40)))
               (i64.or
                  (i64.shl (i64.extend_i32_u
                              (array.get_u $string (local.get $s)
                                 (i32.add (local.get $p) (i32.const 6))))
                           (i64.const 48))
                  (i64.shl (i64.extend_i32_u
                              (array.get_u $string (local.get $s)
                                 (i32.add (local.get $p) (i32.const 7))))
                           (i64.const 56)))))))

   (func (export "caml_bytes_set16")
      (param (ref eq) (ref eq) (ref eq)) (result (ref eq))
      (local $s (ref $string)) (local $p i32) (local $v i32)
      (local.set $s (ref.cast $string (local.get 0)))
      (local.set $p (i31.get_s (ref.cast i31 (local.get 1))))
      (local.set $v (i31.get_s (ref.cast i31 (local.get 2))))
      (if (i32.lt_s (local.get $p) (i32.const 0))
         (then (call $caml_bound_error)))
      (if (i32.ge_u (i32.add (local.get $p) (i32.const 1))
                    (array.len (local.get $s)))
         (then (call $caml_bound_error)))
      (array.set $string (local.get $s) (local.get $p) (local.get $v))
      (array.set $string (local.get $s)
         (i32.add (local.get $p) (i32.const 1))
         (i32.shr_u (local.get $v) (i32.const 8)))
      (i31.new (i32.const 0)))

   (func (export "caml_bytes_set32")
      (param (ref eq) (ref eq) (ref eq)) (result (ref eq))
      (local $s (ref $string)) (local $p i32) (local $v i32)
      (local.set $s (ref.cast $string (local.get 0)))
      (local.set $p (i31.get_s (ref.cast i31 (local.get 1))))
      (local.set $v (struct.get $int32 1 (ref.cast $int32 (local.get 2))))
      (if (i32.lt_s (local.get $p) (i32.const 0))
         (then (call $caml_bound_error)))
      (if (i32.ge_u (i32.add (local.get $p) (i32.const 3))
                    (array.len (local.get $s)))
         (then (call $caml_bound_error)))
      (array.set $string (local.get $s) (local.get $p) (local.get $v))
      (array.set $string (local.get $s)
         (i32.add (local.get $p) (i32.const 1))
         (i32.shr_u (local.get $v) (i32.const 8)))
      (array.set $string (local.get $s)
         (i32.add (local.get $p) (i32.const 2))
         (i32.shr_u (local.get $v) (i32.const 16)))
      (array.set $string (local.get $s)
         (i32.add (local.get $p) (i32.const 3))
         (i32.shr_u (local.get $v) (i32.const 24)))
      (i31.new (i32.const 0)))

   (func (export "caml_bytes_set64")
      (param (ref eq) (ref eq) (ref eq)) (result (ref eq))
      (local $s (ref $string)) (local $p i32) (local $v i64)
      (local.set $s (ref.cast $string (local.get 0)))
      (local.set $p (i31.get_s (ref.cast i31 (local.get 1))))
      (local.set $v (struct.get $int64 1 (ref.cast $int64 (local.get 2))))
      (if (i32.lt_s (local.get $p) (i32.const 0))
         (then (call $caml_bound_error)))
      (if (i32.ge_u (i32.add (local.get $p) (i32.const 7))
                    (array.len (local.get $s)))
         (then (call $caml_bound_error)))
      (array.set $string (local.get $s) (local.get $p)
         (i32.wrap_i64 (local.get $v)))
      (array.set $string (local.get $s)
         (i32.add (local.get $p) (i32.const 1))
         (i32.wrap_i64 (i64.shr_u (local.get $v) (i64.const 8))))
      (array.set $string (local.get $s)
         (i32.add (local.get $p) (i32.const 2))
         (i32.wrap_i64 (i64.shr_u (local.get $v) (i64.const 16))))
      (array.set $string (local.get $s)
         (i32.add (local.get $p) (i32.const 3))
         (i32.wrap_i64 (i64.shr_u (local.get $v) (i64.const 24))))
      (array.set $string (local.get $s)
         (i32.add (local.get $p) (i32.const 4))
         (i32.wrap_i64 (i64.shr_u (local.get $v) (i64.const 32))))
      (array.set $string (local.get $s)
         (i32.add (local.get $p) (i32.const 5))
         (i32.wrap_i64 (i64.shr_u (local.get $v) (i64.const 40))))
      (array.set $string (local.get $s)
         (i32.add (local.get $p) (i32.const 6))
         (i32.wrap_i64 (i64.shr_u (local.get $v) (i64.const 48))))
      (array.set $string (local.get $s)
         (i32.add (local.get $p) (i32.const 7))
         (i32.wrap_i64 (i64.shr_u (local.get $v) (i64.const 56))))
      (i31.new (i32.const 0)))
)
