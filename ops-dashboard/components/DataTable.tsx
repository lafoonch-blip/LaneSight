import { Fragment } from "react";

export interface Column<T> {
  key: keyof T | string;
  label: string;
  num?: boolean;
  render?: (row: T) => string;
}

// Generic table. A null/undefined cell renders the NO DATA dash (—), never 0-as-fake.
export function DataTable<T>({
  columns, rows, caption,
}: {
  columns: Column<T>[];
  rows: T[];
  caption?: string;
}) {
  return (
    <div className="card">
      <div className="table-scroll">
        <table>
          {caption ? <caption style={{ display: "none" }}>{caption}</caption> : null}
          <thead>
            <tr>{columns.map((c) => <th key={String(c.key)} className={c.num ? "num" : undefined}>{c.label}</th>)}</tr>
          </thead>
          <tbody>
            {rows.map((row, i) => (
              <tr key={i}>
                {columns.map((c) => {
                  const raw = c.render ? c.render(row) : row[c.key as keyof T];
                  const display = raw === null || raw === undefined || raw === "" ? "—" : String(raw);
                  return <td key={String(c.key)} className={c.num ? "num" : undefined}>{display}</td>;
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export { Fragment };
