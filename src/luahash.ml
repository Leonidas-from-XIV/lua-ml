(***********************************************************************)
(*                                                                     *)
(*                           Objective Caml                            *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the GNU Library General Public License.         *)
(*                                                                     *)
(***********************************************************************)

(* $Id: luahash.nw,v 1.8 2004-08-03 22:13:33 nr Exp $ *)

(* Hash tables *)

let hash_param = Hashtbl.hash_param

let hash x = hash_param 10 100 x

(* We do dynamic hashing, and resize the table and rehash the elements
   when buckets become too long. *)

type ('a, 'b) t =
  { eq : 'a -> 'a -> bool;
    mutable population : int;
    mutable max_len: int;                     (* max length of a bucket *)
    mutable data: ('a, 'b) bucketlist array } (* the buckets *)

and ('a, 'b) bucketlist =
    Empty
  | Cons of 'a * 'b * ('a, 'b) bucketlist

let bucket_length l =
  let rec len k = function
    | Empty -> k
    | Cons(_, _, l) -> len (k+1) l
  in len 0 l

let dump_buckets h k i l =
  let nsize = Array.length h.data in
  let int = string_of_int in
  let hmod k = int (hash k mod nsize) in
  let rec dump = function
    | Empty -> ()
    | Cons (k', i', l) ->
        List.iter prerr_string ["New bucket hash = "; int (hash k'); " [mod=";
                                hmod k'; "]"; 
                                if h.eq k k' then " (identical " else " (different ";
                                "keys)\n"];
        dump l
  in List.iter prerr_string ["First bucket hash = "; string_of_int (hash k);
                             " [mod="; hmod k; "]\n"];
     dump l

let create eq initial_size =
  let s = if initial_size < 1 then 1 else initial_size in
  let s = if s > Sys.max_array_length then Sys.max_array_length else s in
  { eq = eq; max_len = 3; data = Array.make s Empty; population = 0 }

let clear h =
  h.population <- 0;
  for i = 0 to Array.length h.data - 1 do
    h.data.(i) <- Empty
  done

let dump_table_stats h =
  let flt x = Printf.sprintf "%4.2f" x in
  let int = string_of_int in
  let sum = ref 0 in
  let sumsq = ref 0 in
  let n   = ref 0 in
  let zs  = ref 0 in
  let ratio n m = float n /. float m in
  let inc r n = r := !r + n in
  let stats l =
    let k = bucket_length l in
    if k = 0 then inc zs 1
    else (inc sum k; inc sumsq (k*k); inc n 1) in
  for i = 0 to Array.length h.data - 1 do
    stats h.data.(i)
  done;
  let mean = ratio (!sum) (!n) in
  let variance = 
    if !n > 1 then                         (* concrete math p 378 *)
      (float (!sumsq) -. float (!sum) *. mean) /. (float (!n - 1))
    else
      0.0 in
  let variance = if variance < 0.0 then 0.0 else variance in
  let stddev = sqrt variance in
  let stderr = stddev /. sqrt (float (!n)) in
  List.iter prerr_string ["Table has "; int (!zs); " empy buckets; ";
                          "avg nonzero length is "; flt (ratio (!sum) (!n));
                          " +/- "; flt stderr; " \n"]


let resize hashfun tbl =
  let odata = tbl.data in
  let osize = Array.length odata in
  let nsize = min (2 * osize + 1) Sys.max_array_length in
  if nsize <> osize then begin
    let ndata = Array.create nsize Empty in
    let rec insert_bucket = function
        Empty -> ()
      | Cons(key, data, rest) ->
          insert_bucket rest; (* preserve original order of elements *)
          let nidx = (hashfun key) mod nsize in
          ndata.(nidx) <- Cons(key, data, ndata.(nidx)) in
    for i = 0 to osize - 1 do
      insert_bucket odata.(i)
    done;
    tbl.data <- ndata;
  end;
  tbl.max_len <- 2 * tbl.max_len
(*  if tbl.max_len >= 48 then dump_table_stats tbl *)

let rec bucket_too_long n bucket =
  if n < 0 then true else
    match bucket with
      Empty -> false
    | Cons(_,_,rest) -> bucket_too_long (n - 1) rest

let remove h key =
  let rec remove_bucket = function
      Empty ->
        Empty
    | Cons(k, i, next) ->
        if h.eq k key then
          begin
            h.population <- h.population - 1;
            next
          end
        else
          Cons(k, i, remove_bucket next) in
  let i = (hash key) mod (Array.length h.data) in
  h.data.(i) <- remove_bucket h.data.(i)

let rec find_rec eq key = function
    Empty ->
      raise Not_found
  | Cons(k, d, rest) ->
      if eq key k then d else find_rec eq key rest

let find h key =
  match h.data.((hash key) mod (Array.length h.data)) with
    Empty -> raise Not_found
  | Cons(k1, d1, rest1) ->
      if h.eq key k1 then d1 else
      match rest1 with
        Empty -> raise Not_found
      | Cons(k2, d2, rest2) ->
          if h.eq key k2 then d2 else
          match rest2 with
            Empty -> raise Not_found
          | Cons(k3, d3, rest3) ->
              if h.eq key k3 then d3 else find_rec h.eq key rest3

(* next element in table starting in bucket [index] *)
let rec next_at h index =
  if index = Array.length h.data then
    raise Not_found
  else
    match h.data.(index) with
    | Empty -> next_at h (index+1)
    | Cons(k1, d1, _) -> (k1, d1)

let rec following eq key fail = 
  let finish = function
    | Empty -> fail ()
    | Cons (k, d, _) -> (k, d)
  in function
  | Empty -> assert false
  | Cons(k1, d1, rest1) ->
      if eq key k1 then finish rest1 else
      following eq key fail rest1

let next h key =
  let index = (hash key) mod (Array.length h.data) in
  let finish = function
    | Empty -> next_at h (index+1)
    | Cons (k, d, _) -> (k, d)
  in 
  match h.data.(index) with
    Empty -> next_at h (index+1)
  | Cons(k1, _, rest1) ->
      if h.eq key k1 then finish rest1 else
      match rest1 with
        Empty -> raise Not_found
      | Cons(k2, _, rest2) ->
          if h.eq key k2 then finish rest2 else
          match rest2 with
            Empty -> raise Not_found
          | Cons(k3, _, rest3) ->
              if h.eq key k3 then finish rest3
              else following h.eq key (fun () -> finish Empty) rest3

let rec first_at h index =
  if index = Array.length h.data then
    raise Not_found
  else
    match h.data.(index) with
    | Empty -> first_at h (index+1)
    | Cons(k, d, _) -> (k, d)

let first h = first_at h 0

let find_all h key =
  let rec find_in_bucket = function
    Empty ->
      []
  | Cons(k, d, rest) ->
      if k = key then d :: find_in_bucket rest else find_in_bucket rest in
  find_in_bucket h.data.((hash key) mod (Array.length h.data))

let replace h ~key ~data:info =
  let rec replace_bucket = function
      Empty ->
        raise Not_found
    | Cons(k, i, next) ->
        if k = key
        then Cons(k, info, next)
        else Cons(k, i, replace_bucket next) in
  let i = (hash key) mod (Array.length h.data) in
  let l = h.data.(i) in
(*
  Log.bucket_length (bucket_length l);
  if bucket_length l > 5 then
    begin
      (match l with Cons (k, i, l) -> dump_buckets h k i l | _ -> ());
      prerr_string
          (if bucket_too_long h.max_len l then "bucket too long (> "
           else "bucket length OK (<= ");
      prerr_int h.max_len;
      prerr_string ")\n\n"
    end;
*)
  try
    h.data.(i) <- replace_bucket l
  with Not_found ->
    begin
      let bucket = Cons(key, info, l) in
      h.data.(i) <- bucket;
      h.population <- h.population + 1;
      (*if bucket_too_long h.max_len bucket then resize hash h*)
      if h.population > Array.length h.data then resize hash h
    end

let mem h key =
  let rec mem_in_bucket = function
  | Empty ->
      false
  | Cons(k, d, rest) ->
      k = key || mem_in_bucket rest in
  mem_in_bucket h.data.((hash key) mod (Array.length h.data))

let iter f h =
  let rec do_bucket = function
      Empty ->
        ()
    | Cons(k, d, rest) ->
        f k d; do_bucket rest in
  let d = h.data in
  for i = 0 to Array.length d - 1 do
    do_bucket d.(i)
  done

let population h =
  h.population
