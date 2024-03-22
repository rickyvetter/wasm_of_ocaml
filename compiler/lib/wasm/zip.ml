open Stdlib

module type CRC = sig
  type t

  val start : t

  val update : bytes -> int -> int -> t -> t

  val finish : t -> int32
end

module CRC32 : CRC = struct
  let compute_table () =
    let open Int32 in
    let tbl = Array.make 256 zero in
    let poly = 0xedb88320l in
    for i = 0 to 255 do
      let n = ref (of_int i) in
      for _ = 0 to 7 do
        if logand !n one = one
        then n := logxor (shift_right_logical !n 1) poly
        else n := shift_right_logical !n 1
      done;
      tbl.(i) <- !n
    done;
    tbl

  module CRC32 : CRC with type t = int32 = struct
    type t = int32

    let table = lazy (compute_table ())

    let start = 0xffffffffl

    let update s pos len crc =
      assert (pos >= 0 && len >= 0 && pos <= Bytes.length s - len);
      let open Int32 in
      let tbl = Lazy.force table in
      let crc = ref crc in
      for i = pos to pos + len - 1 do
        crc :=
          logxor
            (shift_right_logical !crc 8)
            (Array.unsafe_get
               tbl
               (to_int !crc land 0xff lxor Char.code (Bytes.unsafe_get s i)))
      done;
      !crc

    let finish crc = Int32.(logxor crc start)
  end

  module CRC64 : CRC with type t = int = struct
    type t = int

    let start = (1 lsl 32) - 1

    let next_table tbl tbl' =
      lazy
        (let tbl = Lazy.force tbl in
         let tbl' = Lazy.force tbl' in
         Array.init 256 ~f:(fun i -> (tbl'.(i) lsr 8) lxor tbl.(tbl'.(i) land 0xFF)))

    let table1 =
      lazy (Array.map ~f:(fun i -> Int32.to_int i land start) (compute_table ()))

    let table2 = next_table table1 table1

    let table3 = next_table table1 table2

    let table4 = next_table table1 table3

    let table5 = next_table table1 table4

    let table6 = next_table table1 table5

    let table7 = next_table table1 table6

    let table8 = next_table table1 table7

    let update s pos len crc =
      assert (pos >= 0 && len >= 0 && pos <= Bytes.length s - len);
      let tbl1 = Lazy.force table1 in
      let tbl2 = Lazy.force table2 in
      let tbl3 = Lazy.force table3 in
      let tbl4 = Lazy.force table4 in
      let tbl5 = Lazy.force table5 in
      let tbl6 = Lazy.force table6 in
      let tbl7 = Lazy.force table7 in
      let tbl8 = Lazy.force table8 in
      let crc = ref crc in
      for i = 0 to (len / 8) - 1 do
        let pos = pos + (i lsl 3) in
        crc :=
          let crc = !crc in
          Array.unsafe_get tbl8 (crc lxor Char.code (Bytes.unsafe_get s pos) land 0xff)
          lxor Array.unsafe_get
                 tbl7
                 ((crc lsr 8) lxor Char.code (Bytes.unsafe_get s (pos + 1)) land 0xff)
          lxor (Array.unsafe_get
                  tbl6
                  ((crc lsr 16) lxor Char.code (Bytes.unsafe_get s (pos + 2)) land 0xff)
               lxor Array.unsafe_get
                      tbl5
                      ((crc lsr 24) lxor Char.code (Bytes.unsafe_get s (pos + 3))))
          lxor (Array.unsafe_get tbl4 (Char.code (Bytes.unsafe_get s (pos + 4)))
               lxor Array.unsafe_get tbl3 (Char.code (Bytes.unsafe_get s (pos + 5)))
               lxor Array.unsafe_get tbl2 (Char.code (Bytes.unsafe_get s (pos + 6)))
               lxor Array.unsafe_get tbl1 (Char.code (Bytes.unsafe_get s (pos + 7))))
      done;
      for i = pos + (len land -8) to pos + len - 1 do
        crc :=
          (!crc lsr 8)
          lxor Array.unsafe_get tbl1 (!crc land 0xff lxor Char.code (Bytes.unsafe_get s i))
      done;
      !crc

    let finish crc = Int32.of_int (crc lxor start)
  end

  module Repr = Sys.Immediate64.Make (Int) (Int32)

  include
    (val match Repr.repr with
         | Immediate -> (module CRC64 : CRC)
         | Non_immediate -> (module CRC32 : CRC)
        : CRC)
end

type file =
  { name : string
  ; pos : int
  ; len : int
  ; mutable crc : int32
  }

type t =
  { ch : out_channel
  ; mutable files : file list
  }

let open_out name = { ch = open_out name; files = [] }

let output_16 ch c =
  output_byte ch c;
  output_byte ch (c lsr 8)

let output_32 ch c =
  output_16 ch c;
  output_16 ch (c lsr 16)

let output_crc ch crc =
  output_16 ch (Int32.to_int crc);
  output_16 ch (Int32.to_int (Int32.shift_right_logical crc 16))

let output_local_file_header ch { name; len; _ } =
  output_32 ch 0x04034b50;
  (* version needed to extract *)
  output_16 ch 10;
  (* general purpose but flag *)
  output_16 ch 0x0;
  (* compression method *)
  output_16 ch 0x0;
  (* time / date *)
  output_16 ch 0x0;
  output_16 ch 0x5821;
  (* CRC *)
  let crc_pos = pos_out ch in
  output_32 ch 0x0;
  (* compressed / uncompressed size *)
  output_32 ch len;
  output_32 ch len;
  (* file name length *)
  output_16 ch (String.length name);
  (* extra field length *)
  output_16 ch 0;
  (* file name *)
  output_string ch name;
  crc_pos

let add_file z ~name ~file =
  let ch = open_in file in
  let pos = pos_out z.ch in
  let len = in_channel_length ch in
  let file = { name; pos; len; crc = 0l } in
  z.files <- file :: z.files;
  let crc_pos = output_local_file_header z.ch file in
  let b = Bytes.create 65536 in
  let crc = ref CRC32.start in
  let rec copy rem =
    if rem > 0
    then (
      let n = input ch b 0 (min 65536 rem) in
      if n = 0 then raise End_of_file;
      crc := CRC32.update b 0 n !crc;
      output z.ch b 0 n;
      copy (rem - n))
  in
  copy len;
  let crc = CRC32.finish !crc in
  file.crc <- crc;
  let pos = pos_out z.ch in
  seek_out z.ch crc_pos;
  output_crc z.ch crc;
  seek_out z.ch pos

let output_file_header ch { name; pos; len; crc } =
  output_32 ch 0x02014b50;
  (* versions: made by / needed to extract *)
  output_16 ch 10;
  output_16 ch 10;
  (* general purpose but flag *)
  output_16 ch 0x0;
  (* compression method *)
  output_16 ch 0x0;
  (* time / date *)
  output_16 ch 0x0;
  output_16 ch 0x5821;
  (* CRC *)
  output_crc ch crc;
  (* compressed / uncompressed size *)
  output_32 ch len;
  output_32 ch len;
  (* file name length *)
  output_16 ch (String.length name);
  (* extra field length *)
  output_16 ch 0;
  (* file comment length *)
  output_16 ch 0;
  (* disk number start *)
  output_16 ch 0;
  (* file attributes *)
  output_16 ch 0;
  output_32 ch 0;
  (* relative offset of local header *)
  output_32 ch pos;
  (* file name *)
  output_string ch name

let output_end_of_directory z pos len =
  let ch = z.ch in
  output_32 ch 0x06054b50;
  (* disk numbers *)
  output_16 ch 0;
  output_16 ch 0;
  (* number of entries *)
  let n = List.length z.files in
  output_16 ch n;
  output_16 ch n;
  (* size of the central directory *)
  output_32 ch len;
  (* offset of the central directory *)
  output_32 ch pos;
  (* comment length *)
  output_16 ch 0

let output_directory z =
  let pos = pos_out z.ch in
  List.iter ~f:(output_file_header z.ch) (List.rev z.files);
  let pos' = pos_out z.ch in
  output_end_of_directory z pos (pos' - pos)

let close_out z =
  output_directory z;
  close_out z.ch
