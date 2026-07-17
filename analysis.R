# Read only the first 50,000 rows so it loads fast while we explore.
# We'll work out which columns matter before touching the full 2.2M rows.
loans <- read_csv("accepted_2007_to_2018Q4.csv", n_max = 50000)

# First look: see the top few rows and the overall structure
glimpse(loans)

# Outcome column = loan_status. Shortlist of ~13 useful columns identified.
# NEXT: write the ONE business question, then keep only those columns.

# BUSINESS QUESTION
# Does Lending Club's interest rate adequately compensate for the
# default risk it takes on across loan grades (A-G)?
#
# Approach: for each grade, compare what it EARNS (avg interest rate)
# against what it LOSES (default rate on resolved loans). If the loss
# rate rises faster than the rate charged, lower grades are underpriced.
#
# Decision it informs: should the lender reprice or tighten approval
# for specific grades?
#
# SCOPE / LIMITATIONS (state these in the README):
#  - Using first 50,000 rows, not a random sample across 2007-2018.
#  - Only RESOLVED loans count: "Fully Paid" vs "Charged Off"/"Default".
#    "Current" loans have unknown outcomes and must be excluded.

# What outcomes exist, and how common is each?
loans %>%
  count(loan_status, sort = TRUE)

# Keep only loans that reached an outcome. "Current"/"Late"/"In Grace Period"
# are still running - we don't know how they end, so counting them would
# make every grade look artificially safe.
resolved <- loans %>%
  filter(loan_status %in% c("Fully Paid", "Charged Off", "Default")) %>%
  mutate(defaulted = loan_status != "Fully Paid")

resolved %>% count(defaulted)

# THE CORE ANALYSIS
# For each grade, what does it EARN and what does it LOSE?
grade_summary <- resolved %>%
  group_by(grade) %>%
  summarise(
    n_loans      = n(),
    avg_int_rate = mean(int_rate),
    default_rate = mean(defaulted)
  ) %>%
  arrange(grade)

grade_summary

# FINDING (crude, first pass):
# Interest rate rises ~4x from A (6.8%) to G (27.6%).
# Default rate rises ~10.7x from A (5.3%) to G (56.5%).
# Risk scales far faster than price. Only grade A charges more than
# its own default rate.
#
# CAVEAT: not yet a valid comparison. int_rate is ANNUAL; default_rate
# is LIFETIME. And a default doesn't lose 100% of principal (borrowers
# repay some before charging off). Next step: compute realised return
# per grade using total_pymnt vs funded_amnt.

# REALISED RETURN PER GRADE
# For every $1 lent, how much came back? This folds interest, defaults,
# partial recoveries and loan term into one comparable number.
grade_returns <- resolved %>%
  group_by(grade) %>%
  summarise(
    n_loans        = n(),
    total_lent     = sum(funded_amnt),
    total_returned = sum(total_pymnt),
    default_rate   = mean(defaulted),
    return_per_1   = total_returned / total_lent,
    net_margin_pct = (return_per_1 - 1) * 100
  ) %>%
  arrange(grade)

grade_returns

# FINDING (defensible version):
# Realised return per $1 lent, by grade:
#   A 1.06 | B 1.05 | C 1.02 | D 0.964 | E 0.903 | F 0.864 | G 0.849
# Break-even sits between grades C and D. Every loan graded D or below
# returned less capital than was advanced.
#
# The pricing model directionally recognises risk (G charges 4x A's rate)
# but under-prices it: G defaults ~10.7x more often than A while charging
# only ~4x the rate. Correcting for term and partial recovery, grades
# D-G destroyed capital in this sample.
#
# CAVEATS: no discounting for time value of money; grades F (n=830) and
# G (n=191) are small samples; first 50k rows are not a random sample.

# THE HEADLINE CHART
# Return per $1 lent by grade, with break-even reference at 1.0.
# Bars above the line made money; bars below destroyed capital.
library(scales)  # for clean % and currency formatting

ggplot(grade_returns, aes(x = grade, y = return_per_1, fill = return_per_1 > 1)) +
  geom_col() +
  geom_hline(yintercept = 1, linetype = "dashed") +
  scale_fill_manual(values = c("TRUE" = "#2E7D32", "FALSE" = "#C62828"),
                    guide = "none") +
  labs(
    title    = "Only the top grades cover their own risk",
    subtitle = "Realised return per $1 lent, by loan grade (resolved loans)",
    x        = "Loan grade",
    y        = "Return per $1 lent"
  ) +
  theme_minimal()

# Save the chart to the project folder for the GitHub repo
ggsave("return_by_grade.png", width = 8, height = 5, dpi = 300)

# SUPPORTING CHART: does price keep pace with risk?
# Both rise with grade — the question is whether they rise together.
grade_summary %>%
  select(grade, avg_int_rate, default_rate) %>%
  mutate(default_rate = default_rate * 100) %>%   # both on a % scale
  pivot_longer(cols = c(avg_int_rate, default_rate),
               names_to = "measure", values_to = "pct") %>%
  ggplot(aes(x = grade, y = pct, colour = measure, group = measure)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  scale_colour_manual(
    values = c("avg_int_rate" = "#1565C0", "default_rate" = "#C62828"),
    labels = c("Interest rate charged", "Default rate"),
    name = NULL
  ) +
  labs(
    title    = "Risk rises faster than the price charged for it",
    subtitle = "Interest rate vs default rate by grade (resolved loans)",
    x = "Loan grade", y = "Percent"
  ) +
  theme_minimal()

ggsave("rate_vs_default.png", width = 8, height = 5, dpi = 300)