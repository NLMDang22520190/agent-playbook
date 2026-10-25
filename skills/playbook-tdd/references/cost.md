# Cost logging

- Log each role run: `bash ~/.agents/playbook/scripts/cost.sh add --role <role> --tokens <N>
  --seconds <S> --model <M> --weight <Full|Lite> --phase <spec|red|green|review|fix|release> --rework <N>
  --majors <N> --task <id>`, with tokens as the harness reports them (`0` if unknown, never a guess); `--rework` is the
  rework round (0 = first pass) and `--majors` the review majors found. Then put `cost.sh summary` into the
  final report's Cost section.
- Optional calibration: when role runs were logged with `--task <id>`, `cost.sh calibrate` shows per weight the
  review majors and rework rounds per task; advice only.
