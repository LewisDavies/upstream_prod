select id, env from {{ ref('stg__defer_prod') }}
